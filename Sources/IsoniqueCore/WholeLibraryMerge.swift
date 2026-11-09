import Foundation

public struct LibraryMergeProjectPreview: Sendable {
    public let name: String
    public let isNew: Bool
    public let photosToAdd: Int
    public let matchingPhotos: Int
}

public struct LibraryMergePreview: Sendable {
    public let projects: [LibraryMergeProjectPreview]
    public let albumsToAdd: Int
    public let originalsToCopy: Int
    public let reusableOriginals: Int
    public let sharedOriginalsInSource: Int
    public let trashedPhotosExcluded: Int
    public let conflicts: [String]

    public var photosToAdd: Int { projects.reduce(0) { $0 + $1.photosToAdd } }
}

public extension LibraryRepository {
    /// Compare catalogues without opening or creating either library and without reading original files.
    func previewLibraryMerge(from folder: URL) throws -> LibraryMergePreview {
        let sourceRoot = try wholeLibraryMergeSource(folder)
        let (_, source) = try LibraryBackup.readCatalogue(sourceRoot)
        let (_, destination) = try LibraryBackup.readCatalogue(root)
        return try WholeLibraryMergePlan(source: source, destination: destination).preview
    }
}

private extension LibraryRepository {
    func wholeLibraryMergeSource(_ folder: URL) throws -> URL {
        let sourceRoot = try otherLibraryRoot(folder)
        guard !sourceRoot.path.hasPrefix(root.path + "/"), !root.path.hasPrefix(sourceRoot.path + "/") else {
            throw LibraryError.unsafePath
        }
        return sourceRoot
    }
}

private struct WholeLibraryMergePlan {
    let preview: LibraryMergePreview
    let newProjects: [Collection]
    let newAlbums: [Collection]
    let newPhotos: [Photo]
    let incomingOriginals: [Photo]
    let existingOriginals: [UUID: Photo]

    init(source: Library, destination: Library) throws {
        let sourceOriginals = try source.uniqueOriginals()
        let destinationOriginals = try destination.uniqueOriginals()
        let sourceProjectIDs = Set(source.projects.map(\.id))
        let destinationProjectIDs = Set(destination.projects.map(\.id))
        let sourceAlbumIDs = Set(source.albums.map(\.id))
        let destinationAlbumIDs = Set(destination.albums.map(\.id))
        guard sourceProjectIDs.count == source.projects.count, sourceAlbumIDs.count == source.albums.count,
              destinationProjectIDs.count == destination.projects.count, destinationAlbumIDs.count == destination.albums.count,
              source.projects.allSatisfy({ $0.rule == nil }), destination.projects.allSatisfy({ $0.rule == nil }) else {
            throw LibraryError.integrity("duplicate or invalid project or album identity")
        }

        let currentPhotos = Dictionary(uniqueKeysWithValues: destination.photos.map { ($0.id, $0) })
        let currentOriginals = Dictionary(uniqueKeysWithValues: destinationOriginals.map { ($0.originalID, $0) })
        let currentAlbums = Dictionary(uniqueKeysWithValues: destination.albums.map { ($0.id, $0) })
        let incomingProjects = source.projects.filter { !destinationProjectIDs.contains($0.id) }
        let incomingAlbums = source.albums.filter { !destinationAlbumIDs.contains($0.id) }
        let sourceRegularAlbums = Set(source.albums.filter { $0.rule == nil }.map(\.id))
        let active = source.activePhotos
        var additions: [Photo] = []
        var additionCounts: [UUID?: Int] = [:]
        var matchCounts: [UUID?: Int] = [:]
        var sourceUses: [UUID: Int] = [:]
        var conflicts: [String] = []
        for photo in active {
            try Task.checkCancellation()
            guard photo.projectID.map(sourceProjectIDs.contains) ?? true else {
                throw LibraryError.integrity("missing project for \(photo.displayName)")
            }
            sourceUses[photo.originalID, default: 0] += 1
            if let current = currentPhotos[photo.id] {
                if current.originalID != photo.originalID {
                    conflicts.append("Photo identity — \(photo.displayName) points to a different original.")
                } else {
                    matchCounts[photo.projectID, default: 0] += 1
                }
            } else {
                guard photo.albumIDs.isSubset(of: sourceRegularAlbums) else {
                    throw LibraryError.integrity("missing regular album for \(photo.displayName)")
                }
                if photo.sharedOriginalID != nil, currentOriginals[photo.id] != nil {
                    conflicts.append("Photo identity — \(photo.displayName) uses the ID of an existing original.")
                }
                additions.append(photo)
                additionCounts[photo.projectID, default: 0] += 1
            }
        }
        for album in source.albums {
            try Task.checkCancellation()
            if let current = currentAlbums[album.id], (current.rule == nil) != (album.rule == nil) {
                conflicts.append("Album identity — \(album.name) is regular in one library and smart in the other.")
            }
            if let project = album.rule?.projectID, !sourceProjectIDs.contains(project) {
                throw LibraryError.integrity("missing project for Smart Album \(album.name)")
            }
        }
        for original in sourceOriginals where sourceUses[original.originalID] != nil {
            try Task.checkCancellation()
            if let current = currentOriginals[original.originalID], current.sha256 != original.sha256 {
                conflicts.append("Original fingerprint — \(original.originalName) has different bytes recorded for the same ID.")
            } else if currentPhotos[original.originalID]?.sharedOriginalID != nil {
                conflicts.append("Original identity — \(original.originalName) uses the ID of an existing version.")
            }
        }

        var projects = source.projects.map {
            LibraryMergeProjectPreview(name: $0.name, isNew: !destinationProjectIDs.contains($0.id),
                                       photosToAdd: additionCounts[$0.id, default: 0],
                                       matchingPhotos: matchCounts[$0.id, default: 0])
        }
        if additionCounts[nil] != nil || matchCounts[nil] != nil {
            projects.append(LibraryMergeProjectPreview(name: "Unassigned photos", isNew: false,
                                                        photosToAdd: additionCounts[nil, default: 0],
                                                        matchingPhotos: matchCounts[nil, default: 0]))
        }
        let neededIDs = Set(additions.map(\.originalID))
        let needed = sourceOriginals.filter { neededIDs.contains($0.originalID) }
        let reused = needed.filter { currentOriginals[$0.originalID]?.sha256 == $0.sha256 }.count
        preview = LibraryMergePreview(projects: projects, albumsToAdd: incomingAlbums.count,
                                      originalsToCopy: needed.filter { currentOriginals[$0.originalID] == nil }.count,
                                      reusableOriginals: reused, sharedOriginalsInSource: sourceUses.values.filter { $0 > 1 }.count,
                                      trashedPhotosExcluded: source.photos.count - active.count, conflicts: conflicts)
        newProjects = incomingProjects
        newAlbums = incomingAlbums
        newPhotos = additions
        incomingOriginals = needed
        existingOriginals = currentOriginals
    }
}
