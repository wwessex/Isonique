import Foundation

public enum ProjectMergePreference: Sendable {
    case current, incoming
}

public struct ProjectLibraryMergeResult {
    public let library: Library
    public let project: Collection
    public fileprivate(set) var added = 0
    public fileprivate(set) var updated = 0
    public fileprivate(set) var trashed = 0
    public fileprivate(set) var skipped = 0
}

public extension LibraryRepository {
    /// Merge an edited export into its matching project by stable catalogue identity.
    func mergeProjectLibrary(from folder: URL, prefer preference: ProjectMergePreference, applyTrash: Bool = false,
                             progress: (ImportProgress) async -> Void = { _ in }) async throws -> ProjectLibraryMergeResult {
        let (sourceRoot, source, project) = try readProjectLibrary(from: folder, allowTrashed: true)
        let (catalogue, destination) = try LibraryBackup.readCatalogue(root)
        guard let current = destination.projects.first(where: { $0.id == project.id }) else {
            throw LibraryError.integrity("the exported project's ID does not match a project in this library")
        }
        let incomingOriginals = try source.uniqueOriginals()
        let existingOriginals = Dictionary(uniqueKeysWithValues: try destination.uniqueOriginals().map { ($0.originalID, $0) })
        let indices = Dictionary(uniqueKeysWithValues: destination.photos.enumerated().map { ($0.element.id, $0.offset) })
        let incomingIDs = Set(source.activePhotos.map(\.id))
        let protectedPhotos = destination.photos.filter {
            $0.projectID != project.id || $0.trashedAt != nil || !incomingIDs.contains($0.id)
        }
        let protectedStacks = Set(protectedPhotos.compactMap(\.stackID))
        let protectedPairs = Set(protectedPhotos.compactMap(\.pairID))
        var knownStacks: Set<UUID> = [], knownPairs: Set<UUID> = []
        for photo in source.photos {
            guard let index = indices[photo.id] else { continue }
            let existing = destination.photos[index]
            guard existing.originalID == photo.originalID, existing.sha256 == photo.sha256 else {
                throw LibraryError.integrity("photo identity conflicts for \(photo.displayName)")
            }
            guard existing.projectID == project.id else { continue }
            if let stackID = photo.stackID, stackID == existing.stackID { knownStacks.insert(stackID) }
            if let pairID = photo.pairID, pairID == existing.pairID { knownPairs.insert(pairID) }
        }
        for original in incomingOriginals {
            if let existing = existingOriginals[original.originalID], existing.sha256 != original.sha256 {
                throw LibraryError.integrity("original identity conflicts for \(original.originalName)")
            }
        }

        var result = ProjectLibraryMergeResult(library: destination, project: current)
        var draft = destination
        draft.version = max(source.version, destination.version)
        let currentAlbumIDs = Set(destination.albums.map(\.id))
        let newAlbums = source.albums.filter { !currentAlbumIDs.contains($0.id) }
        for album in newAlbums {
            var copy = album
            copy.rule?.projectID = project.id
            if copy.rule != nil { draft.version = max(draft.version, 2) }
            draft.albums.append(copy)
        }
        let regularIDs = Set(draft.albums.filter { $0.rule == nil }.map(\.id))
        let sourceRegularIDs = Set(source.albums.filter { $0.rule == nil }.map(\.id)).intersection(regularIDs)
        let newRegularIDs = Set(newAlbums.map(\.id)).intersection(regularIDs)

        var reservedNames = Set(destination.photos.map { $0.filename.lowercased() })
        var copiedNames: [UUID: String] = [:]
        var appliedStackPhotos: Set<UUID> = []
        var checkedOriginals: Set<UUID> = []
        for photo in source.photos {
            try Task.checkCancellation()
            if let index = indices[photo.id] {
                let existing = destination.photos[index]
                guard existing.projectID == project.id else { result.skipped += 1; continue }
                if let deleted = photo.trashedAt {
                    if applyTrash && existing.trashedAt == nil {
                        draft.photos[index].trashedAt = deleted
                        result.trashed += 1
                    }
                    continue
                }
                guard existing.trashedAt == nil else { result.skipped += 1; continue }
                var merged = existing
                if preference == .incoming {
                    merged = photo
                    merged.useOriginal(from: existing)
                    merged.albumIDs = existing.albumIDs.subtracting(sourceRegularIDs)
                        .union(photo.albumIDs.intersection(sourceRegularIDs))
                    if let stackID = existing.stackID, protectedStacks.contains(stackID) {
                        merged.stackID = stackID
                    } else if let stackID = photo.stackID, protectedStacks.contains(stackID), !knownStacks.contains(stackID) {
                        merged.stackID = existing.stackID
                    }
                    if let pairID = existing.pairID, protectedPairs.contains(pairID) {
                        merged.pairID = pairID
                    } else if let pairID = photo.pairID, protectedPairs.contains(pairID), !knownPairs.contains(pairID) {
                        merged.pairID = existing.pairID
                    }
                    appliedStackPhotos.insert(photo.id)
                } else {
                    merged.albumIDs.formUnion(photo.albumIDs.intersection(newRegularIDs))
                }
                if merged != existing {
                    draft.photos[index] = merged
                }
            } else if photo.trashedAt == nil {
                var copy = photo
                copy.albumIDs.formIntersection(sourceRegularIDs)
                if let stackID = photo.stackID, protectedStacks.contains(stackID), !knownStacks.contains(stackID) { copy.stackID = nil }
                if let pairID = photo.pairID, protectedPairs.contains(pairID), !knownPairs.contains(pairID) { copy.pairID = nil }
                if let existing = existingOriginals[photo.originalID] {
                    if checkedOriginals.insert(photo.originalID).inserted {
                        try Self.verifyOriginal(availableOriginalURL(existing), photo: existing)
                    }
                    copy.useOriginal(from: existing)
                } else {
                    if copiedNames[photo.originalID] == nil {
                        copiedNames[photo.originalID] = nextProjectOriginalFilename(photo.filename, reserved: &reservedNames)
                    }
                    guard let filename = copiedNames[photo.originalID] else { throw LibraryError.integrity(photo.originalName) }
                    copy.filename = filename
                }
                draft.photos.append(copy)
                appliedStackPhotos.insert(photo.id)
                result.added += 1
            }
        }
        let existingStacks = Set(destination.photos.compactMap(\.stackID))
        let existingPairs = Set(destination.photos.compactMap(\.pairID))
        draft.dropIncompleteNewGroups(existingStacks: existingStacks, existingPairs: existingPairs)
        result.updated = zip(destination.photos, draft.photos).lazy.filter {
            $0.0.trashedAt == $0.1.trashedAt && $0.0 != $0.1
        }.count
        let excludedPresentation = preference == .current
            ? protectedStacks.union(existingStacks) : protectedStacks
        draft.mergeStackPresentation(source.stackBrowser ?? StackBrowserState(), appliedPhotos: appliedStackPhotos,
                                     excludedStacks: excludedPresentation, regularAlbums: sourceRegularIDs)
        try draft.validateSchema()
        _ = try draft.uniqueOriginals()
        let transfers = incomingOriginals.map { (original: $0, filename: copiedNames[$0.originalID]) }
        try await commitProjectLibrary(draft, catalogue: catalogue, sourceRoot: sourceRoot,
                                       transfers: transfers, progress: progress)
        return ProjectLibraryMergeResult(library: draft, project: current, added: result.added,
                                         updated: result.updated, trashed: result.trashed, skipped: result.skipped)
    }
}

private extension Library {
    mutating func dropIncompleteNewGroups(existingStacks: Set<UUID>, existingPairs: Set<UUID>) {
        var counts: [UUID: Int] = [:]
        var pairs: [UUID: Set<UUID>] = [:]
        for photo in photos {
            if let stackID = photo.stackID, !existingStacks.contains(stackID) { counts[stackID, default: 0] += 1 }
            if let pairID = photo.pairID, !existingPairs.contains(pairID) { pairs[pairID, default: []].insert(photo.originalID) }
        }
        for index in photos.indices {
            if let stackID = photos[index].stackID, counts[stackID] == 1 { photos[index].stackID = nil }
            if let pairID = photos[index].pairID, pairs[pairID]?.count == 1 { photos[index].pairID = nil }
        }
    }

    mutating func mergeStackPresentation(_ source: StackBrowserState, appliedPhotos: Set<UUID>,
                                         excludedStacks: Set<UUID>, regularAlbums: Set<UUID>) {
        guard !appliedPhotos.isEmpty else { return }
        let byID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let appliedStacks = Set(appliedPhotos.compactMap { byID[$0]?.stackID }).subtracting(excludedStacks)
        var state = stackBrowser ?? StackBrowserState()
        for stackID in appliedStacks {
            state.setCollapsed(source.collapsed.contains(stackID), stackID: stackID)
        }
        for (stackID, photoID) in source.picks where appliedStacks.contains(stackID) {
            guard appliedPhotos.contains(photoID), byID[photoID]?.stackID == stackID else { continue }
            _ = state.apply(StackPickChange(stackID: stackID, photoID: photoID, selectionID: photoID))
        }
        for (albumID, picks) in source.albumPicks where regularAlbums.contains(albumID) {
            for (stackID, photoID) in picks where appliedStacks.contains(stackID) {
                guard appliedPhotos.contains(photoID), let photo = byID[photoID], photo.stackID == stackID,
                      photo.albumIDs.contains(albumID) else { continue }
                _ = state.apply(StackPickChange(stackID: stackID, albumID: albumID, photoID: photoID, selectionID: photoID))
            }
        }
        if state != StackBrowserState() { stackBrowser = state; version = max(version, 3) }
        else { stackBrowser = nil }
    }
}
