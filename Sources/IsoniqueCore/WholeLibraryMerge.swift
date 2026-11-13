import Foundation

public enum LibraryMergePhotoPolicy: Sendable {
    case addOnly, preferCurrent, preferIncoming

    fileprivate var preference: ProjectMergePreference? {
        switch self {
        case .addOnly: return nil
        case .preferCurrent: return .current
        case .preferIncoming: return .incoming
        }
    }
}

public struct LibraryMergePhotoDifference: Sendable {
    public let photoName: String
    public let projectName: String?
    public let fields: [String]
}

public struct LibraryMergeTrashMove: Sendable {
    public let photoID: UUID
    public let photoName: String
    public let projectName: String?
}

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
    public let photoPolicy: LibraryMergePhotoPolicy
    public let photoDifferences: [LibraryMergePhotoDifference]
    public let trashMoves: [LibraryMergeTrashMove]

    public var photosToAdd: Int { projects.reduce(0) { $0 + $1.photosToAdd } }
    public var hasAdditions: Bool { photosToAdd > 0 || albumsToAdd > 0 || projects.contains(where: \.isNew) }
    public var photosToUpdate: Int { photoPolicy == .preferIncoming ? photoDifferences.count : 0 }
    public var hasChanges: Bool { hasAdditions || photosToUpdate > 0 || !trashMoves.isEmpty }
}

public struct LibraryMergeResult {
    public let library: Library
    public let preview: LibraryMergePreview
}

public enum LibraryMergeError: LocalizedError {
    case identityConflicts

    public var errorDescription: String? {
        "Identity conflicts prevent this library merge."
    }
}

public extension LibraryRepository {
    /// Compare catalogues without opening or creating either library and without reading original files.
    func previewLibraryMerge(from folder: URL, photoPolicy: LibraryMergePhotoPolicy = .addOnly,
                             applyTrash: Bool = false, reserving history: EditHistory? = nil) throws -> LibraryMergePreview {
        let sourceRoot = try wholeLibraryMergeSource(folder)
        let (_, source) = try LibraryBackup.readCatalogue(sourceRoot)
        let (_, destination) = try LibraryBackup.readCatalogue(root)
        return try WholeLibraryMergePlan(source: source, destination: destination, photoPolicy: photoPolicy,
                                         applyTrash: applyTrash, history: history).preview
    }

    /// Add compatible records and optionally reconcile edits or explicit Trash on matching photos.
    func mergeLibrary(from folder: URL, photoPolicy: LibraryMergePhotoPolicy = .addOnly, applyTrash: Bool = false,
                      reserving history: EditHistory? = nil, basedOn workspace: Library? = nil,
                      review: (LibraryMergePreview) async -> Bool,
                      progress: (ImportProgress) async -> Void = { _ in }) async throws -> LibraryMergeResult {
        let sourceRoot = try wholeLibraryMergeSource(folder)
        let (sourceCatalogue, source) = try LibraryBackup.readCatalogue(sourceRoot)
        let (catalogue, destination) = try LibraryBackup.readCatalogue(root)
        try checkWorkspaceCatalogue(workspace, matches: destination)
        let plan = try WholeLibraryMergePlan(source: source, destination: destination, photoPolicy: photoPolicy,
                                             applyTrash: applyTrash, history: history)
        try Task.checkCancellation()
        let approved = await review(plan.preview)
        try Task.checkCancellation()
        guard plan.preview.conflicts.isEmpty else { throw LibraryMergeError.identityConflicts }
        guard approved else { throw CancellationError() }
        guard plan.preview.hasChanges else { return LibraryMergeResult(library: destination, preview: plan.preview) }

        var originalsToVerify = Set(plan.updatedPhotos.values.map(\.originalID))
        var reservedNames = Set(destination.photos.map { $0.filename.lowercased() })
        var names: [UUID: String] = [:]
        var transfers: [(original: Photo, filename: String?)] = []
        for original in plan.incomingOriginals {
            try Task.checkCancellation()
            if let existing = plan.existingOriginals[original.originalID] {
                originalsToVerify.insert(existing.originalID)
            } else {
                let name = nextProjectOriginalFilename(original.filename, reserved: &reservedNames)
                names[original.originalID] = name
                transfers.append((original, name))
            }
        }
        for id in originalsToVerify {
            try Task.checkCancellation()
            guard let original = plan.existingOriginals[id] else { throw LibraryError.integrity("missing matching original") }
            try Self.verifyOriginal(availableOriginalURL(original), photo: original)
        }
        let draft = try plan.applying(to: destination, source: source, filenames: names)
        let saved = try await commitLibraryTransfer(draft, catalogue: catalogue, sourceRoot: sourceRoot,
                                                    sourceCatalogue: sourceCatalogue, transfers: transfers, progress: progress)
        return LibraryMergeResult(library: saved, preview: plan.preview)
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
    let updatedPhotos: [UUID: Photo]
    let trashDates: [UUID: Date]
    let incomingOriginals: [Photo]
    let existingOriginals: [UUID: Photo]
    let occupiedStacks: Set<UUID>
    let occupiedPairs: Set<UUID>

    init(source: Library, destination: Library, photoPolicy: LibraryMergePhotoPolicy, applyTrash: Bool,
         history: EditHistory?) throws {
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
        let currentProjectNames = Dictionary(uniqueKeysWithValues: destination.projects.map { ($0.id, $0.name) })
        let currentOriginals = Dictionary(uniqueKeysWithValues: destinationOriginals.map { ($0.originalID, $0) })
        let currentAlbums = Dictionary(uniqueKeysWithValues: destination.albums.map { ($0.id, $0) })
        let historyEntries = (destination.history?.undo ?? []) + (destination.history?.redo ?? [])
            + (history?.undo ?? []) + (history?.redo ?? [])
        let historicPhotos = historyEntries.compactMap(\.photo)
        let historicPicks = historyEntries.compactMap { entry -> StackPickChange? in
            if case .stackPick(let pick) = entry { return pick }
            return nil
        }
        let reservedPhotoIDs = Set(historyEntries.compactMap(\.selectionID) + historicPicks.compactMap(\.photoID)
            + historyEntries.flatMap(\.groupedPhotoIDs))
        let currentPresentation = destination.stackBrowser ?? StackBrowserState()
        let storedPhotos = destination.photos + historicPhotos
        var storedStacks = Set(storedPhotos.compactMap(\.stackID))
        storedStacks.formUnion(currentPresentation.collapsed)
        storedStacks.formUnion(currentPresentation.picks.keys)
        storedStacks.formUnion(currentPresentation.albumPicks.values.flatMap(\.keys))
        storedStacks.formUnion(historicPicks.map(\.stackID))
        let storedPairs = Set(storedPhotos.compactMap(\.pairID))
        let incomingProjects = source.projects.filter { !destinationProjectIDs.contains($0.id) }
        let incomingAlbums = source.albums.filter { !destinationAlbumIDs.contains($0.id) }
        let sourceRegularAlbums = Set(source.albums.filter { $0.rule == nil }.map(\.id))
        let active = source.activePhotos
        var additions: [Photo] = []
        var updates: [UUID: Photo] = [:]
        var differences: [LibraryMergePhotoDifference] = []
        var additionCounts: [UUID?: Int] = [:]
        var matchCounts: [UUID?: Int] = [:]
        var sourceUses: [UUID: Int] = [:]
        var conflicts: [String] = []
        var sharedStacks: Set<UUID> = [], sharedPairs: Set<UUID> = []
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
                    if current.trashedAt == nil {
                        if let stackID = photo.stackID, current.stackID == stackID { sharedStacks.insert(stackID) }
                        if let pairID = photo.pairID, current.pairID == pairID { sharedPairs.insert(pairID) }
                        if let preference = photoPolicy.preference, current.sha256 == photo.sha256 {
                            let edit = ProjectPhotoMergeValues.mergingEditableValues(current, with: photo, baseline: nil,
                                                                                      prefer: preference)
                            if !edit.conflicts.isEmpty {
                                differences.append(LibraryMergePhotoDifference(
                                    photoName: current.displayName, projectName: current.projectID.flatMap { currentProjectNames[$0] },
                                    fields: edit.conflicts))
                            }
                            if edit.photo != current { updates[current.id] = edit.photo }
                        }
                    }
                }
            } else {
                guard photo.albumIDs.isSubset(of: sourceRegularAlbums) else {
                    throw LibraryError.integrity("missing regular album for \(photo.displayName)")
                }
                if photo.sharedOriginalID != nil, currentOriginals[photo.id] != nil {
                    conflicts.append("Photo identity — \(photo.displayName) uses the ID of an existing original.")
                }
                if reservedPhotoIDs.contains(photo.id) {
                    conflicts.append("Photo identity — \(photo.displayName) uses an ID reserved by destination edit history.")
                }
                additions.append(photo)
                additionCounts[photo.projectID, default: 0] += 1
            }
        }
        var moves: [LibraryMergeTrashMove] = []
        var dates: [UUID: Date] = [:]
        if applyTrash {
            for photo in source.photos {
                try Task.checkCancellation()
                guard let date = photo.trashedAt, let current = currentPhotos[photo.id],
                      current.trashedAt == nil else { continue }
                guard current.originalID == photo.originalID, current.sha256 == photo.sha256,
                      !current.sha256.isEmpty else {
                    conflicts.append("Trash identity — \(current.displayName) does not have a matching original ID and fingerprint.")
                    continue
                }
                dates[current.id] = date
                moves.append(LibraryMergeTrashMove(photoID: current.id, photoName: current.displayName,
                                                   projectName: current.projectID.flatMap { currentProjectNames[$0] }))
            }
        }
        var stackConflicts: Set<UUID> = [], pairConflicts: Set<UUID> = []
        for photo in additions {
            try Task.checkCancellation()
            if let id = photo.stackID, storedStacks.contains(id), !sharedStacks.contains(id),
               stackConflicts.insert(id).inserted {
                conflicts.append("Stack identity — \(photo.displayName) belongs to a stack with no matching member in the current library.")
            }
            if let id = photo.pairID, storedPairs.contains(id), !sharedPairs.contains(id),
               pairConflicts.insert(id).inserted {
                conflicts.append("RAW+JPEG pair identity — \(photo.displayName) belongs to a pair with no matching member in the current library.")
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
                                      trashedPhotosExcluded: source.photos.count - active.count - moves.count,
                                      conflicts: conflicts, photoPolicy: photoPolicy, photoDifferences: differences, trashMoves: moves)
        newProjects = incomingProjects
        newAlbums = incomingAlbums
        newPhotos = additions
        updatedPhotos = updates
        trashDates = dates
        incomingOriginals = needed
        existingOriginals = currentOriginals
        occupiedStacks = storedStacks
        occupiedPairs = storedPairs
    }

    func applying(to destination: Library, source: Library, filenames: [UUID: String]) throws -> Library {
        var draft = destination
        draft.version = max(destination.version, source.version)
        draft.projects.append(contentsOf: newProjects)
        draft.albums.append(contentsOf: newAlbums)
        if !updatedPhotos.isEmpty || !trashDates.isEmpty {
            for index in draft.photos.indices {
                try Task.checkCancellation()
                let id = draft.photos[index].id
                if let updated = updatedPhotos[id] { draft.photos[index] = updated }
                if let date = trashDates[id] { draft.photos[index].trashedAt = date }
            }
        }
        var newStackCounts: [UUID: Int] = [:]
        var newPairOriginals: [UUID: Set<UUID>] = [:]
        for photo in newPhotos {
            if let id = photo.stackID, !occupiedStacks.contains(id) { newStackCounts[id, default: 0] += 1 }
            if let id = photo.pairID, !occupiedPairs.contains(id) { newPairOriginals[id, default: []].insert(photo.originalID) }
        }
        let newStacks = Set(newStackCounts.filter { StackRules.canStack(photoCount: $0.value) }.keys)
        var addedStackMembers: [UUID: Photo] = [:]
        for photo in newPhotos {
            try Task.checkCancellation()
            var copy = photo
            if let existing = existingOriginals[photo.originalID] {
                copy.useOriginal(from: existing)
            } else if let name = filenames[photo.originalID] {
                copy.filename = name
                copy.referencedPath = nil
            } else {
                throw LibraryError.integrity(photo.originalName)
            }
            if let id = copy.stackID, !occupiedStacks.contains(id) {
                if newStacks.contains(id) { addedStackMembers[copy.id] = copy }
                else { copy.stackID = nil }
            }
            if let id = copy.pairID, newPairOriginals[id]?.count == 1 { copy.pairID = nil }
            draft.photos.append(copy)
        }
        if let state = source.stackBrowser {
            for id in state.collapsed.intersection(newStacks) { draft.setStackCollapsed(true, stackID: id) }
            for (id, pick) in state.picks where addedStackMembers[pick]?.stackID == id {
                draft.applyStackPick(StackPickChange(stackID: id, photoID: pick, selectionID: pick))
            }
            for (albumID, picks) in state.albumPicks {
                for (id, pick) in picks {
                    guard let photo = addedStackMembers[pick], photo.stackID == id, photo.albumIDs.contains(albumID) else { continue }
                    draft.applyStackPick(StackPickChange(stackID: id, albumID: albumID, photoID: pick, selectionID: pick))
                }
            }
        }
        if let incomingOrders = source.browserOrders {
            var orders = draft.browserOrders ?? BrowserOrderState()
            let activeIDs = Set(draft.activePhotos.map(\.id))
            let incomingAll = incomingOrders.ids(in: "all").filter(activeIDs.contains)
            if !incomingAll.isEmpty {
                var combined = orders.ids(in: "all")
                if combined.isEmpty {
                    combined = destination.activePhotos.sorted {
                        $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt < $1.importedAt
                    }.map(\.id)
                }
                for id in incomingAll where !combined.contains(id) { combined.append(id) }
                orders.set(combined, in: "all")
            }
            for project in newProjects {
                let scope = "project:\(project.id)"
                orders.set(incomingOrders.ids(in: scope).filter(activeIDs.contains), in: scope)
            }
            for album in newAlbums where album.rule == nil {
                let scope = "album:\(album.id)"
                orders.set(incomingOrders.ids(in: scope).filter(activeIDs.contains), in: scope)
            }
            if !orders.isEmpty { draft.browserOrders = orders; draft.upgradeForBrowserOrders() }
        }
        try draft.validateSchema()
        _ = try draft.uniqueOriginals()
        return draft
    }
}
