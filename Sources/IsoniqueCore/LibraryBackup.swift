import Foundation

/// Independent Isonique backups. Does not read or repair Apple's catalogues.
public enum LibraryBackup {
    private struct Manifest: Codable {
        var version = 1
        var catalogSHA256: String
        var originals: [String: String]
    }
    private struct Snapshot {
        var data: Data
        var library: Library
        var originals: [String: String]
    }

    private static func regularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath }
    }
    private static func read(_ folder: URL, allowMissingManaged: Bool = false) throws -> Snapshot {
        let catalog = folder.appendingPathComponent("catalog.json")
        try regularFile(catalog)
        let data = try Data(contentsOf: catalog)
        let library = try JSONDecoder().decode(Library.self, from: data)
        try library.validateSchema()
        let originals = folder.appendingPathComponent("Originals")
        guard originals.resolvingSymlinksInPath() == originals else { throw LibraryError.unsafePath }
        var hashes: [String: String] = [:]
        for photo in try library.uniqueOriginals() {
            guard !photo.filename.isEmpty, photo.filename != ".", photo.filename != "..",
                  photo.filename == (photo.filename as NSString).lastPathComponent else { throw LibraryError.unsafePath }
            if let path = photo.referencedPath {
                _ = try LibraryRepository.referenceURL(path, libraryRoot: folder)
                continue
            }
            let url = originals.appendingPathComponent(photo.filename)
            if allowMissingManaged {
                do { try regularFile(url) }
                catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                    continue
                }
            } else {
                try regularFile(url)
            }
            guard try LibraryRepository.digest(url) == photo.sha256 else { throw LibraryError.integrity(photo.originalName) }
            hashes[photo.filename] = photo.sha256
        }
        return Snapshot(data: data, library: library, originals: hashes)
    }

    /// Reads every catalogue-referenced original without modifying any library files.
    public static func verify(_ repository: LibraryRepository) throws -> Int {
        let library = try read(repository.root).library
        let originals = try library.uniqueOriginals()
        for photo in originals where photo.referencedPath != nil {
            let url = try repository.availableOriginalURL(photo)
            guard try LibraryRepository.digest(url) == photo.sha256 else { throw LibraryError.integrity(photo.originalName) }
        }
        return originals.count
    }

    /// Check every present managed original and allow a missing file to be relinked in the workspace.
    public static func openVerified(_ source: URL) throws -> (LibraryRepository, Library) {
        let root = source.standardizedFileURL.resolvingSymlinksInPath()
        _ = try read(root, allowMissingManaged: true)
        let repository = try LibraryRepository(root: root)
        return (repository, try repository.load())
    }

    public static func create(from repository: LibraryRepository, to destination: URL) throws {
        let snapshot = try read(repository.root)
        try copy(snapshot, from: repository.root, to: destination, excluding: repository.root)
    }

    /// Always restores to a new folder, leaving both the source and current library intact.
    public static func restore(from source: URL, to destination: URL, excluding current: URL?) throws {
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let snapshot = try readBackup(source)
        try copy(snapshot, from: source, to: destination, excluding: current)
    }

    public static func validateBackup(_ source: URL) throws -> Int {
        try readBackup(source.standardizedFileURL.resolvingSymlinksInPath()).library.photos.count
    }

    private static func readBackup(_ source: URL) throws -> Snapshot {
        let manifestURL = source.appendingPathComponent("backup-manifest.json")
        try regularFile(manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1 else { throw LibraryError.unsupportedVersion }
        guard try LibraryRepository.digest(source.appendingPathComponent("catalog.json")) == manifest.catalogSHA256 else {
            throw LibraryError.integrity("backup catalogue")
        }
        let snapshot = try read(source)
        guard snapshot.originals == manifest.originals else { throw LibraryError.integrity("backup manifest") }
        return snapshot
    }

    private static func copy(_ snapshot: Snapshot, from source: URL, to destination: URL, excluding current: URL?) throws {
        let fm = FileManager.default
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        for protected in [source, current].compactMap({ $0 }) {
            let protected = protected.standardizedFileURL.resolvingSymlinksInPath()
            guard target != protected, !target.path.hasPrefix(protected.path + "/") else { throw LibraryError.unsafePath }
        }
        guard !fm.fileExists(atPath: target.path),
              !target.pathComponents.contains(where: { ["aplibrary", "aperturelibrary", "photolibrary", "photoslibrary", "app"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else { throw LibraryError.unsafePath }
        let parent = target.deletingLastPathComponent()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard fm.isWritableFile(atPath: parent.path) else { throw CocoaError(.fileWriteNoPermission) }
        let staging = target.deletingLastPathComponent().appendingPathComponent(".isonique-backup-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        try fm.createDirectory(at: staging.appendingPathComponent("Originals"), withIntermediateDirectories: false)
        try snapshot.data.write(to: staging.appendingPathComponent("catalog.json"), options: .withoutOverwriting)
        for name in snapshot.originals.keys {
            try fm.copyItem(at: source.appendingPathComponent("Originals").appendingPathComponent(name),
                            to: staging.appendingPathComponent("Originals").appendingPathComponent(name))
        }
        // Verify copied bytes before publishing the destination folder.
        let copied = try read(staging)
        guard copied.data == snapshot.data, copied.originals == snapshot.originals else { throw LibraryError.integrity("copied library") }
        let manifest = Manifest(catalogSHA256: try LibraryRepository.digest(staging.appendingPathComponent("catalog.json")), originals: snapshot.originals)
        try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("backup-manifest.json"), options: .withoutOverwriting)
        try fm.moveItem(at: staging, to: target)
    }
}
