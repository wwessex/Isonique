import Foundation

public struct OriginalRelocationReport: Sendable {
    public fileprivate(set) var relocated: [String] = []
    public fileprivate(set) var unavailable: [String] = []
    public fileprivate(set) var occupied: [String] = []
    public fileprivate(set) var failed: [String] = []
    public fileprivate(set) var renamed: [String] = []
    public fileprivate(set) var retained: [String] = []
    public fileprivate(set) var alreadyInFolder: [String] = []
}

public extension LibraryRepository {
    /// Copy selected originals to a new folder, update their references, then release eligible old copies.
    func relocateOriginals(_ originalIDs: Set<UUID>, to folder: URL, in library: inout Library,
                           keepReferencedSources: Bool = true) throws -> OriginalRelocationReport {
        try relocateOriginals(originalIDs, to: folder, in: &library, keepReferencedSources: keepReferencedSources) { source in
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
        }
    }

    internal func relocateOriginals(_ originalIDs: Set<UUID>, to folder: URL, in library: inout Library,
                                    keepReferencedSources: Bool = true, trashSource: (URL) throws -> Void) throws -> OriginalRelocationReport {
        try Task.checkCancellation()
        guard folder.isFileURL else { throw LibraryError.unsafePath }
        let directory = try Self.referenceURL(folder.path, libraryRoot: root)
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw LibraryError.unsafePath }

        let catalogue = root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let originals = try library.uniqueOriginals().filter { originalIDs.contains($0.originalID) }
        var report = OriginalRelocationReport()
        var transfers: [(photo: Photo, source: URL, destination: URL)] = []
        for photo in originals {
            try Task.checkCancellation()
            guard let source = try? availableOriginalURL(photo) else {
                report.unavailable.append(photo.originalName)
                continue
            }
            if photo.referencedPath != nil, sameRelocationDirectory(source.deletingLastPathComponent(), directory) {
                report.alreadyInFolder.append(photo.originalName)
                continue
            }
            do {
                guard let destination = try relocationDestination(for: photo, from: source, in: directory) else {
                    report.occupied.append(photo.originalName)
                    continue
                }
                transfers.append((photo, source, destination))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.failed.append(photo.originalName)
            }
        }
        guard !transfers.isEmpty else { return report }

        var paths: [UUID: String] = [:]
        for transfer in transfers {
            try Task.checkCancellation()
            let resolved = try Self.referenceURL(transfer.destination.path, libraryRoot: root)
            guard resolved.path == transfer.destination.path else { throw LibraryError.unsafePath }
            try Self.verifyOriginal(resolved, photo: transfer.photo)
            paths[transfer.photo.originalID] = resolved.path
        }
        var updated = library
        updated.version = max(updated.version, 2)
        for index in updated.photos.indices {
            if let path = paths[updated.photos[index].originalID] { updated.photos[index].referencedPath = path }
        }
        try Task.checkCancellation()
        guard try Data(contentsOf: catalogue) == before else { throw LibraryError.integrity("catalogue changed during relocation") }
        try save(updated)
        library = updated

        // Keep files that another catalogue record, including Trash, still references.
        let movesReferences = !keepReferencedSources && transfers.contains { $0.photo.referencedPath != nil }
        let referencedPaths = movesReferences
            ? Set(Set(updated.photos.compactMap(\.referencedPath)).map(relocationPathKey))
            : []
        var releasedSources: Set<String> = []
        for transfer in transfers {
            let photo = transfer.photo
            report.relocated.append(photo.originalName)
            if transfer.destination.lastPathComponent != relocationName(for: photo, source: transfer.source) {
                report.renamed.append(transfer.destination.lastPathComponent)
            }
            if photo.referencedPath != nil &&
                (keepReferencedSources || referencedPaths.contains(relocationPathKey(transfer.source.path))) {
                report.retained.append(photo.originalName)
                continue
            }
            if releasedSources.contains(transfer.source.path) { continue }
            do {
                // A committed reference can go offline before cleanup. Keep the source in that case.
                try Task.checkCancellation()
                try Self.verifyOriginal(transfer.destination, photo: photo)
                try Self.verifyOriginal(transfer.source, photo: photo)
                try trashSource(transfer.source)
                releasedSources.insert(transfer.source.path)
            } catch {
                report.retained.append(photo.originalName)
            }
        }
        return report
    }

    private func relocationPathKey(_ path: String) -> String {
        // Conservatively keep aliases on volumes that ignore case or Unicode composition.
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func sameRelocationDirectory(_ lhs: URL, _ rhs: URL) -> Bool {
        if lhs.path == rhs.path { return true }
        let files = FileManager.default
        guard let left = try? files.attributesOfItem(atPath: lhs.path),
              let right = try? files.attributesOfItem(atPath: rhs.path),
              let volume = left[.systemNumber] as? NSNumber,
              let inode = left[.systemFileNumber] as? NSNumber else { return false }
        return volume == right[.systemNumber] as? NSNumber && inode == right[.systemFileNumber] as? NSNumber
    }

    private func relocationName(for photo: Photo, source: URL) -> String {
        let name = photo.referencedPath == nil ? (photo.sourceName ?? photo.originalName) : source.lastPathComponent
        guard name == (name as NSString).lastPathComponent, !name.isEmpty, name != ".", name != "..",
              !name.contains(":"), !name.contains("\0") else { return photo.filename }
        return name
    }

    private func relocationDestination(for photo: Photo, from source: URL, in directory: URL) throws -> URL? {
        let name = relocationName(for: photo, source: source)
        let names = name == photo.filename ? [name] : [name, photo.filename]
        for name in names {
            let destination = directory.appendingPathComponent(name)
            let values = try? destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            if values?.isSymbolicLink == true { continue }
            if FileManager.default.fileExists(atPath: destination.path) {
                // An interrupted run may already have placed an exact copy here.
                guard (try? Self.verifyOriginal(destination, photo: photo)) != nil else { continue }
                try Self.verifyOriginal(source, photo: photo)
            } else {
                try Self.installVerifiedOriginal(from: source, at: destination, photo: photo)
            }
            return destination
        }
        return nil
    }
}
