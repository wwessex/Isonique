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
    public fileprivate(set) var conflicts = 0
    public fileprivate(set) var stackUpdates = 0
    public fileprivate(set) var albumUpdates = 0
}

public struct ProjectPhotoMergeConflict: Sendable {
    public let photoName: String
    public let fields: [String]
}

public struct ProjectStackMergeConflict: Sendable {
    public let representativeName: String
    public let fields: [String]
}

public struct ProjectAlbumMergeConflict: Sendable {
    public let albumName: String
    public let fields: [String]
}

public struct ProjectLibraryMergePreview: Sendable {
    public let projectName: String
    public let added: Int
    public let updated: Int
    public let trashed: Int
    public let skipped: Int
    public let addedAlbums: Int
    public let copiedOriginals: Int
    public let trashNames: [String]
    public let conflicts: [ProjectPhotoMergeConflict]
    public let legacyMatches: Int
    public let stackUpdates: Int
    public let stackConflicts: [ProjectStackMergeConflict]
    public let albumUpdates: Int
    public let albumConflicts: [ProjectAlbumMergeConflict]
}

public extension LibraryRepository {
    /// Merge an edited export into its matching project by stable catalogue identity.
    func mergeProjectLibrary(from folder: URL, prefer preference: ProjectMergePreference, applyTrash: Bool = false,
                             basedOn workspace: Library? = nil,
                             review: (ProjectLibraryMergePreview) async -> Bool = { _ in true },
                             progress: (ImportProgress) async -> Void = { _ in }) async throws -> ProjectLibraryMergeResult {
        let (sourceRoot, source, project) = try readProjectLibrary(from: folder, allowTrashed: true)
        let (catalogue, destination) = try LibraryBackup.readCatalogue(root)
        try checkWorkspaceCatalogue(workspace, matches: destination)
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
        let membership = source.projectExportMembership.flatMap { $0.projectID == project.id ? $0 : nil }
        var albumConflicts: [ProjectAlbumMergeConflict] = []
        if let baseline = membership?.albumDefinitions {
            let definitions = try draft.mergeAlbumDefinitions(from: source.albums, baseline: baseline,
                                                              projectID: project.id, prefer: preference)
            result.albumUpdates = definitions.updated
            albumConflicts = definitions.conflicts
        }
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
        var trashNames: [String] = []
        var conflicts: [ProjectPhotoMergeConflict] = []
        var legacyMatches = 0
        for photo in source.photos {
            try Task.checkCancellation()
            if let index = indices[photo.id] {
                let existing = destination.photos[index]
                guard existing.projectID == project.id else { result.skipped += 1; continue }
                if let deleted = photo.trashedAt {
                    if applyTrash && existing.trashedAt == nil {
                        draft.photos[index].trashedAt = deleted
                        trashNames.append(existing.displayName)
                    }
                    continue
                }
                guard existing.trashedAt == nil else { result.skipped += 1; continue }
                var merged = existing
                var fields: [String] = []
                if let record = membership?.originalsByPhoto[photo.id], record.matches(existing), let baseline = record.values {
                    let values = baseline.merging(existing, with: photo, prefer: preference,
                                                  representedAlbums: sourceRegularIDs, supportsLocationEdits: source.version >= 16)
                    merged = values.photo
                    fields = values.conflicts
                    let stack = resolveProjectValue(existing.stackID, photo.stackID, baseline: baseline.stackID, prefer: preference)
                    let pair = resolveProjectValue(existing.pairID, photo.pairID, baseline: baseline.pairID, prefer: preference)
                    if permitsProjectGroupChange(existing.stackID, to: stack.value, protected: protectedStacks, known: knownStacks) {
                        merged.stackID = stack.value
                        if stack.conflict { fields.append("Stack membership") }
                    }
                    if permitsProjectGroupChange(existing.pairID, to: pair.value, protected: protectedPairs, known: knownPairs) {
                        merged.pairID = pair.value
                        if pair.conflict { fields.append("RAW+JPEG pair") }
                    }
                    appliedStackPhotos.insert(photo.id)
                } else {
                    legacyMatches += 1
                    if preference == .incoming {
                        merged = photo
                        merged.useOriginal(from: existing)
                        if merged.locationOverride == nil { merged.locationOverride = existing.locationOverride }
                        merged.albumIDs = existing.albumIDs.subtracting(sourceRegularIDs)
                            .union(photo.albumIDs.intersection(sourceRegularIDs))
                        if !permitsProjectGroupChange(existing.stackID, to: photo.stackID, protected: protectedStacks, known: knownStacks) {
                            merged.stackID = existing.stackID
                        }
                        if !permitsProjectGroupChange(existing.pairID, to: photo.pairID, protected: protectedPairs, known: knownPairs) {
                            merged.pairID = existing.pairID
                        }
                        appliedStackPhotos.insert(photo.id)
                    } else {
                        merged.albumIDs.formUnion(photo.albumIDs.intersection(newRegularIDs))
                    }
                }
                if !fields.isEmpty { conflicts.append(ProjectPhotoMergeConflict(photoName: existing.displayName, fields: fields)) }
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
        if applyTrash, let membership {
            let exportedIDs = Set(source.photos.map(\.id))
            let trashDate = Date()
            for photo in destination.photos where photo.trashedAt == nil && !exportedIDs.contains(photo.id) {
                try Task.checkCancellation()
                guard let original = membership.originalsByPhoto[photo.id], let index = indices[photo.id] else { continue }
                guard photo.projectID == project.id, original.matches(photo) else {
                    result.skipped += 1
                    continue
                }
                draft.photos[index].trashedAt = trashDate
                trashNames.append(photo.displayName)
            }
        }
        result.trashed = trashNames.count
        let existingStacks = Set(destination.photos.compactMap(\.stackID))
        let existingPairs = Set(destination.photos.compactMap(\.pairID))
        draft.dropIncompleteNewGroups(existingStacks: existingStacks, existingPairs: existingPairs)
        result.updated = zip(destination.photos, draft.photos).lazy.filter {
            $0.0.trashedAt == $0.1.trashedAt && $0.0 != $0.1
        }.count
        var stackConflicts: [ProjectStackMergeConflict] = []
        if let baseline = membership?.stackPresentation {
            let presentation = draft.mergeStackPresentation(from: source, baseline: baseline, prefer: preference,
                                                            appliedPhotos: appliedStackPhotos,
                                                            excludedStacks: protectedStacks, regularAlbums: sourceRegularIDs)
            result.stackUpdates = presentation.updated
            stackConflicts = presentation.conflicts
        } else {
            let excludedPresentation = preference == .current ? protectedStacks.union(existingStacks) : protectedStacks
            result.stackUpdates = draft.mergeLegacyStackPresentation(source.stackBrowser ?? StackBrowserState(),
                                                                     appliedPhotos: appliedStackPhotos,
                                                                     excludedStacks: excludedPresentation,
                                                                     regularAlbums: sourceRegularIDs)
        }
        if let incomingOrders = source.browserOrders {
            var orders = draft.browserOrders ?? BrowserOrderState()
            let projectScope = "project:\(project.id)"
            let preferred = incomingOrders.ids(in: projectScope).isEmpty
                ? incomingOrders.ids(in: "all") : incomingOrders.ids(in: projectScope)
            let projectIDs = Set(draft.photos.filter { $0.trashedAt == nil && $0.projectID == project.id }.map(\.id))
            if preference == .incoming || orders.ids(in: projectScope).isEmpty {
                orders.set(preferred.filter(projectIDs.contains), in: projectScope)
            }
            for album in source.albums where album.rule == nil {
                let scope = "album:\(album.id)"
                let albumIDs = Set(draft.photos.filter { $0.trashedAt == nil && $0.albumIDs.contains(album.id) }.map(\.id))
                if preference == .incoming || orders.ids(in: scope).isEmpty {
                    orders.set(incomingOrders.ids(in: scope).filter(albumIDs.contains), in: scope)
                }
            }
            if !orders.isEmpty { draft.browserOrders = orders; draft.upgradeForBrowserOrders() }
        }
        try draft.validateSchema()
        _ = try draft.uniqueOriginals()
        try Task.checkCancellation()
        let preview = ProjectLibraryMergePreview(projectName: current.name, added: result.added, updated: result.updated,
                                                 trashed: result.trashed, skipped: result.skipped, addedAlbums: newAlbums.count,
                                                 copiedOriginals: copiedNames.count, trashNames: trashNames,
                                                 conflicts: conflicts, legacyMatches: legacyMatches,
                                                 stackUpdates: result.stackUpdates, stackConflicts: stackConflicts,
                                                 albumUpdates: result.albumUpdates, albumConflicts: albumConflicts)
        guard await review(preview) else { throw CancellationError() }
        try Task.checkCancellation()
        let transfers = incomingOriginals.map { (original: $0, filename: copiedNames[$0.originalID]) }
        let saved = try await commitLibraryTransfer(draft, catalogue: catalogue, sourceRoot: sourceRoot,
                                                    transfers: transfers, progress: progress)
        return ProjectLibraryMergeResult(library: saved, project: current, added: result.added,
                                         updated: result.updated, trashed: result.trashed, skipped: result.skipped,
                                         conflicts: conflicts.count + stackConflicts.count + albumConflicts.count,
                                         stackUpdates: result.stackUpdates, albumUpdates: result.albumUpdates)
    }
}

private func permitsProjectGroupChange(_ current: UUID?, to incoming: UUID?, protected: Set<UUID>, known: Set<UUID>) -> Bool {
    if let current, protected.contains(current) { return false }
    if let incoming, protected.contains(incoming), !known.contains(incoming) { return false }
    return true
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

    mutating func mergeLegacyStackPresentation(_ source: StackBrowserState, appliedPhotos: Set<UUID>,
                                               excludedStacks: Set<UUID>, regularAlbums: Set<UUID>) -> Int {
        guard !appliedPhotos.isEmpty else { return 0 }
        let byID = Dictionary(photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let appliedStacks = Set(appliedPhotos.compactMap { byID[$0]?.stackID }).subtracting(excludedStacks)
        var state = stackBrowser ?? StackBrowserState()
        var updated: Set<UUID> = []
        for stackID in appliedStacks where state.collapsed.contains(stackID) != source.collapsed.contains(stackID) {
            state.setCollapsed(source.collapsed.contains(stackID), stackID: stackID)
            updated.insert(stackID)
        }
        for (stackID, photoID) in source.picks where appliedStacks.contains(stackID) {
            guard state.picks[stackID] != photoID, appliedPhotos.contains(photoID),
                  byID[photoID]?.stackID == stackID else { continue }
            _ = state.apply(StackPickChange(stackID: stackID, photoID: photoID, selectionID: photoID))
            updated.insert(stackID)
        }
        for (albumID, picks) in source.albumPicks where regularAlbums.contains(albumID) {
            for (stackID, photoID) in picks where appliedStacks.contains(stackID) {
                guard state.albumPicks[albumID]?[stackID] != photoID, appliedPhotos.contains(photoID),
                      let photo = byID[photoID], photo.stackID == stackID,
                      photo.albumIDs.contains(albumID) else { continue }
                _ = state.apply(StackPickChange(stackID: stackID, albumID: albumID, photoID: photoID, selectionID: photoID))
                updated.insert(stackID)
            }
        }
        if state != StackBrowserState() { stackBrowser = state; version = max(version, 3) }
        else { stackBrowser = nil }
        return updated.count
    }
}
