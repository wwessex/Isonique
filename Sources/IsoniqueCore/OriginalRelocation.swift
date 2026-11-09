import Foundation

public struct OriginalRelocationReport: Sendable {
    public fileprivate(set) var relocated: [String] = []
    public fileprivate(set) var unavailable: [String] = []
    public fileprivate(set) var occupied: [String] = []
    public fileprivate(set) var failed: [String] = []
    public fileprivate(set) var renamed: [String] = []
    public fileprivate(set) var retained: [String] = []
}

public extension LibraryRepository {
    /// Move selected managed originals outside the library and save their new references.
    func relocateManagedOriginals(_ originalIDs: Set<UUID>, to folder: URL,
                                  in library: inout Library) throws -> OriginalRelocationReport {
        try relocateManagedOriginals(originalIDs, to: folder, in: &library) { source in
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
        }
    }

    internal func relocateManagedOriginals(_ originalIDs: Set<UUID>, to folder: URL, in library: inout Library,
                                           trashSource: (URL) throws -> Void) throws -> OriginalRelocationReport {
        try Task.checkCancellation()
        guard folder.isFileURL else { throw LibraryError.unsafePath }
        let directory = try Self.referenceURL(folder.path, libraryRoot: root)
        guard try directory.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw LibraryError.unsafePath }

        let catalogue = root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let originals = try library.uniqueOriginals().filter { $0.referencedPath == nil && originalIDs.contains($0.originalID) }
        var report = OriginalRelocationReport()
        var transfers: [(photo: Photo, source: URL, destination: URL)] = []
        for photo in originals {
            try Task.checkCancellation()
            guard let source = try? availableOriginalURL(photo) else {
                report.unavailable.append(photo.originalName)
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

        for transfer in transfers {
            let photo = transfer.photo
            report.relocated.append(photo.originalName)
            if transfer.destination.lastPathComponent != relocationName(for: photo) {
                report.renamed.append(transfer.destination.lastPathComponent)
            }
            do {
                // A committed reference can go offline before cleanup. Keep the source in that case.
                try Task.checkCancellation()
                try Self.verifyOriginal(transfer.destination, photo: photo)
                try Self.verifyOriginal(transfer.source, photo: photo)
                try trashSource(transfer.source)
            } catch {
                report.retained.append(photo.originalName)
            }
        }
        return report
    }

    private func relocationName(for photo: Photo) -> String {
        let name = photo.sourceName ?? photo.originalName
        guard name == (name as NSString).lastPathComponent, !name.isEmpty, name != ".", name != "..",
              !name.contains(":"), !name.contains("\0") else { return photo.filename }
        return name
    }

    private func relocationDestination(for photo: Photo, from source: URL, in directory: URL) throws -> URL? {
        let name = relocationName(for: photo)
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
