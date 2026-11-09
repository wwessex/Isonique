import Foundation

public struct ProjectLibraryImportResult {
    public let library: Library
    public let project: Collection
    public let photoCount: Int
}

public extension LibraryRepository {
    /// Add an independent project library without merging its records into existing projects.
    func importProjectLibrary(from folder: URL, reserving history: EditHistory? = nil,
                              progress: (ImportProgress) async -> Void = { _ in }) async throws -> ProjectLibraryImportResult {
        let (sourceRoot, source, project) = try readProjectLibrary(from: folder, allowTrashed: false)
        let originals = try source.uniqueOriginals()
        let (catalogue, destination) = try LibraryBackup.readCatalogue(root)
        let plan = try ProjectLibraryImportPlan(source: source, originals: originals, project: project,
                                                destination: destination, history: history)
        let transfers = try originals.map { (original: $0, filename: try plan.filename(for: $0) as String?) }
        try await commitLibraryTransfer(plan.result.library, catalogue: catalogue, sourceRoot: sourceRoot,
                                        transfers: transfers, progress: progress)
        return plan.result
    }

    internal func readProjectLibrary(from folder: URL, allowTrashed: Bool) throws -> (URL, Library, Collection) {
        let sourceRoot = try otherLibraryRoot(folder)
        let (_, source) = try LibraryBackup.readCatalogue(sourceRoot)
        _ = try source.uniqueOriginals()
        return (sourceRoot, source, try source.validateExportedProject(allowTrashed: allowTrashed))
    }

    internal func otherLibraryRoot(_ folder: URL) throws -> URL {
        try Task.checkCancellation()
        guard folder.isFileURL else { throw LibraryError.unsafePath }
        let sourceRoot = folder.standardizedFileURL.resolvingSymlinksInPath()
        try Self.validateRoot(sourceRoot)
        let files = FileManager.default
        let sourceAttributes = try files.attributesOfItem(atPath: sourceRoot.path)
        let destinationAttributes = try files.attributesOfItem(atPath: root.path)
        if let volume = sourceAttributes[.systemNumber] as? NSNumber,
           let inode = sourceAttributes[.systemFileNumber] as? NSNumber,
           volume == destinationAttributes[.systemNumber] as? NSNumber,
           inode == destinationAttributes[.systemFileNumber] as? NSNumber {
            throw LibraryError.unsafePath
        }
        guard sourceRoot.path != root.path else { throw LibraryError.unsafePath }

        return sourceRoot
    }

    internal func commitLibraryTransfer(_ library: Library, catalogue: Data, sourceRoot: URL,
                                        sourceCatalogue: Data? = nil, transfers: [(original: Photo, filename: String?)],
                                        progress: (ImportProgress) async -> Void) async throws {
        let files = FileManager.default
        let staging = root.appendingPathComponent(".isonique-project-import-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }
        for (index, transfer) in transfers.enumerated() {
            try Task.checkCancellation()
            let original = transfer.original
            let input: URL
            if let path = original.referencedPath { input = try Self.referenceURL(path, libraryRoot: sourceRoot) }
            else { input = try Self.managedOriginalURL(original.filename, in: sourceRoot) }
            if let filename = transfer.filename {
                try LibraryBackup.regularFile(input)
                let copy = staging.appendingPathComponent(filename)
                try files.copyItem(at: input, to: copy)
                try Self.verifyOriginal(copy, photo: original)
            } else {
                try Self.verifyOriginal(input, photo: original)
            }
            await progress(ImportProgress(processed: index + 1, total: transfers.count, filename: original.originalName))
        }

        try Task.checkCancellation()
        // Serialize publication with library transfers from this or another process.
        try withCatalogueWriteLock {
            var installed: [URL] = []
            var committed = false
            defer {
                if !committed {
                    for url in installed { try? files.removeItem(at: url) }
                }
            }
            let catalogueURL = root.appendingPathComponent("catalog.json")
            func verifyCatalogues() throws {
                guard try Data(contentsOf: catalogueURL) == catalogue else {
                    throw LibraryError.integrity("destination catalogue changed during transfer; try again")
                }
                if let sourceCatalogue {
                    let sourceURL = sourceRoot.appendingPathComponent("catalog.json")
                    try LibraryBackup.regularFile(sourceURL)
                    guard try Data(contentsOf: sourceURL) == sourceCatalogue else {
                        throw LibraryError.integrity("source catalogue changed during transfer; try again")
                    }
                }
            }
            try verifyCatalogues()
            for filename in transfers.compactMap(\.filename) {
                try Task.checkCancellation()
                let target = try managedOriginalURL(filename)
                try Self.publishStagedItem(staging.appendingPathComponent(filename), at: target)
                installed.append(target)
            }
            try Task.checkCancellation()
            try verifyCatalogues()
            try Task.checkCancellation()
            try writeCatalogue(library)
            committed = true
        }
    }
}

private extension Library {
    func validateExportedProject(allowTrashed: Bool) throws -> Collection {
        guard projects.count == 1, let project = projects.first, project.rule == nil,
              photos.allSatisfy({ $0.projectID == project.id && (allowTrashed || $0.trashedAt == nil) && $0.referencedPath == nil }) else {
            throw LibraryError.integrity("choose a self-contained library from Export Project as Library")
        }
        let albumIDs = Set(albums.map(\.id))
        let regularIDs = Set(albums.filter { $0.rule == nil }.map(\.id))
        guard albumIDs.count == albums.count,
              albums.allSatisfy({ $0.rule?.projectID == nil || $0.rule?.projectID == project.id }),
              photos.allSatisfy({ $0.albumIDs.isSubset(of: regularIDs) }) else {
            throw LibraryError.integrity("project album membership")
        }
        // An edited export can retain presentation picks for a removed version.
        if !allowTrashed, let stackBrowser {
            let photosByID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
            let stackIDs = Set(photos.compactMap(\.stackID))
            guard stackBrowser.collapsed.isSubset(of: stackIDs),
                  stackBrowser.picks.allSatisfy({ photosByID[$0.value]?.stackID == $0.key }),
                  stackBrowser.albumPicks.allSatisfy({ albumID, picks in
                      regularIDs.contains(albumID) && picks.allSatisfy { stackID, photoID in
                          guard let photo = photosByID[photoID] else { return false }
                          return photo.stackID == stackID && photo.albumIDs.contains(albumID)
                      }
                  }) else {
                throw LibraryError.integrity("project stack membership")
            }
        }
        return project
    }
}

private struct ProjectLibraryImportPlan {
    let result: ProjectLibraryImportResult
    private let filenames: [UUID: String]

    init(source: Library, originals: [Photo], project: Collection, destination: Library, history: EditHistory?) throws {
        let historyEntries = (destination.history?.undo ?? []) + (destination.history?.redo ?? [])
            + (history?.undo ?? []) + (history?.redo ?? [])
        let oldPhotos = destination.photos + historyEntries.compactMap(\.photo)
        let oldPicks = historyEntries.compactMap { entry -> StackPickChange? in
            if case .stackPick(let pick) = entry { return pick }
            return nil
        }
        let oldState = destination.stackBrowser ?? StackBrowserState()
        let photoIDs = ProjectImportIDs(source.photos.flatMap { [$0.id, $0.originalID] },
                                        avoiding: oldPhotos.flatMap { [$0.id, $0.originalID] }
                                            + oldPicks.map(\.selectionID) + oldPicks.compactMap(\.photoID))
        let projectIDs = ProjectImportIDs([project.id], avoiding: destination.projects.map(\.id)
            + oldPhotos.compactMap(\.projectID) + destination.albums.compactMap { $0.rule?.projectID })
        let albumIDs = ProjectImportIDs(source.albums.map(\.id), avoiding: destination.albums.map(\.id)
            + oldPhotos.flatMap(\.albumIDs) + Array(oldState.albumPicks.keys) + oldPicks.compactMap(\.albumID))
        let storedStacks = Array(oldState.picks.keys) + Array(oldState.collapsed)
            + oldState.albumPicks.values.flatMap(\.keys) + oldPicks.map(\.stackID)
        let stackIDs = ProjectImportIDs(source.photos.compactMap(\.stackID),
                                         avoiding: oldPhotos.compactMap(\.stackID) + storedStacks)
        let pairIDs = ProjectImportIDs(source.photos.compactMap(\.pairID), avoiding: oldPhotos.compactMap(\.pairID))
        let recipeIDs = ProjectImportIDs(source.photos.flatMap { $0.versions?.map(\.id) ?? [] },
                                         avoiding: oldPhotos.flatMap { $0.versions?.map(\.id) ?? [] })

        var names = Set(oldPhotos.map { $0.filename.lowercased() })
        var copiedNames: [UUID: String] = [:]
        for original in originals {
            copiedNames[original.originalID] = nextProjectOriginalFilename(original.filename, reserved: &names)
        }
        filenames = copiedNames

        var library = destination
        library.version = max(source.version, destination.version)
        if source.albums.contains(where: { $0.rule != nil }) { library.version = max(library.version, 2) }
        var imported = project
        imported.id = projectIDs[project.id]
        var projectNames = Set(library.projects.map(\.name))
        imported.name = Self.availableName(project.name, used: &projectNames)
        library.projects.append(imported)
        var albumNames = Set(library.albums.map(\.name))
        for album in source.albums {
            var copy = album
            copy.id = albumIDs[album.id]
            copy.name = Self.availableName(album.name, used: &albumNames)
            copy.rule?.projectID = imported.id
            library.albums.append(copy)
        }
        for photo in source.photos {
            try Task.checkCancellation()
            var copy = photo
            copy.filename = try Self.filename(for: photo, in: copiedNames)
            copy.id = photoIDs[photo.id]
            copy.sharedOriginalID = photo.sharedOriginalID.map { photoIDs[$0] }
            copy.projectID = imported.id
            copy.albumIDs = Set(photo.albumIDs.map { albumIDs[$0] })
            copy.stackID = photo.stackID.map { stackIDs[$0] }
            copy.pairID = photo.pairID.map { pairIDs[$0] }
            copy.versions = photo.versions?.map { recipe in
                var copy = recipe
                copy.id = recipeIDs[recipe.id]
                return copy
            }
            library.photos.append(copy)
        }
        if let sourceState = source.stackBrowser {
            var state = oldState
            for stackID in sourceState.collapsed {
                state.setCollapsed(true, stackID: stackIDs[stackID])
            }
            for (stackID, photoID) in sourceState.picks {
                let mapped = photoIDs[photoID]
                _ = state.apply(StackPickChange(stackID: stackIDs[stackID], photoID: mapped, selectionID: mapped))
            }
            for (albumID, picks) in sourceState.albumPicks {
                for (stackID, photoID) in picks {
                    let mapped = photoIDs[photoID]
                    _ = state.apply(StackPickChange(stackID: stackIDs[stackID], albumID: albumIDs[albumID],
                                                    photoID: mapped, selectionID: mapped))
                }
            }
            library.stackBrowser = state
        }
        try library.validateSchema()
        _ = try library.uniqueOriginals()
        result = ProjectLibraryImportResult(library: library, project: imported, photoCount: source.photos.count)
    }

    func filename(for photo: Photo) throws -> String { try Self.filename(for: photo, in: filenames) }

    private static func filename(for photo: Photo, in names: [UUID: String]) throws -> String {
        guard let name = names[photo.originalID] else { throw LibraryError.integrity(photo.originalName) }
        return name
    }

    private static func availableName(_ name: String, used: inout Set<String>) -> String {
        if used.insert(name).inserted { return name }
        var number = 2
        while !used.insert("\(name) (\(number))").inserted { number += 1 }
        return "\(name) (\(number))"
    }
}

private struct ProjectImportIDs {
    private var replacements: [UUID: UUID] = [:]

    init(_ incoming: [UUID], avoiding occupied: [UUID]) {
        let incoming = Set(incoming)
        let occupied = Set(occupied)
        var reserved = incoming.union(occupied)
        for id in incoming.intersection(occupied) {
            var replacement: UUID
            repeat { replacement = UUID() } while !reserved.insert(replacement).inserted
            replacements[id] = replacement
        }
    }

    subscript(_ id: UUID) -> UUID { replacements[id] ?? id }
}

func nextProjectOriginalFilename(_ sourceName: String, reserved: inout Set<String>) -> String {
    let suffix = URL(fileURLWithPath: sourceName).pathExtension
    var name: String
    repeat { name = UUID().uuidString + (suffix.isEmpty ? "" : "." + suffix) }
    while !reserved.insert(name.lowercased()).inserted
    return name
}
