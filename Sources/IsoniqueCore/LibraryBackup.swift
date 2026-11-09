import Foundation
import CryptoKit

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

    static func regularFile(_ url: URL) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath }
    }
    static func readCatalogue(_ folder: URL) throws -> (Data, Library) {
        let catalog = folder.appendingPathComponent("catalog.json")
        try regularFile(catalog)
        let data = try Data(contentsOf: catalog)
        return (data, try decodeCatalogue(data))
    }

    static func decodeCatalogue(_ data: Data) throws -> Library {
        var library = try JSONDecoder().decode(Library.self, from: data)
        try library.validateSchema()
        library.catalogueRevision = CatalogueRevision(data)
        return library
    }

    private static func read(_ folder: URL, allowMissingManaged: Bool = false) throws -> Snapshot {
        let (data, library) = try readCatalogue(folder)
        return try readOriginals(in: folder, data: data, library: library, allowMissingManaged: allowMissingManaged)
    }

    private static func readOriginals(in folder: URL, data: Data, library: Library,
                                      allowMissingManaged: Bool = false) throws -> Snapshot {
        let originals = folder.appendingPathComponent("Originals")
        guard originals.resolvingSymlinksInPath() == originals else { throw LibraryError.unsafePath }
        var hashes: [String: String] = [:]
        for photo in try library.uniqueOriginals() {
            try Task.checkCancellation()
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
        return (repository, try repository.reloadCatalogue())
    }

    public static func create(from repository: LibraryRepository, to destination: URL) throws {
        let snapshot = try read(repository.root)
        try copy(snapshot, from: repository.root, to: destination, excluding: repository.root)
    }

    /// Export active project photos as a new library with a local copy of every original.
    @discardableResult
    public static func exportProject(_ projectID: UUID, from repository: LibraryRepository, to destination: URL) throws -> Int {
        try Task.checkCancellation()
        let source = try repository.load()
        let library = try source.catalogueForProjectExport(projectID)
        let selectedIDs = Set(library.photos.map(\.originalID))
        var locations: [String: URL] = [:]
        for original in try source.uniqueOriginals() where selectedIDs.contains(original.originalID) {
            try Task.checkCancellation()
            locations[original.filename] = try repository.availableOriginalURL(original)
        }
        let originals = try library.uniqueOriginals()
        let hashes = Dictionary(uniqueKeysWithValues: originals.map { ($0.filename, $0.sha256) })
        let snapshot = Snapshot(data: try JSONEncoder().encode(library), library: library, originals: hashes)
        try publish(snapshot, to: destination, excluding: [repository.root], writeManifest: false) { name in
            guard let location = locations[name] else { throw LibraryError.integrity(name) }
            return location
        }
        return library.photos.count
    }

    /// Always restores to a new folder, leaving both the source and current library intact.
    public static func restore(from source: URL, to destination: URL, excluding current: URL?) throws {
        let source = source.standardizedFileURL.resolvingSymlinksInPath()
        let snapshot = try readBackup(source)
        try copy(snapshot, from: source, to: destination, excluding: current)
    }

    /// Validate the selected source before asking where to restore it. Restore rechecks it.
    public static func validateBackup(_ source: URL) throws -> Int {
        try readBackup(source.standardizedFileURL.resolvingSymlinksInPath()).library.photos.count
    }

    private static func readBackup(_ source: URL) throws -> Snapshot {
        let (data, library, manifest) = try readBackupCatalogue(source)
        let snapshot = try readOriginals(in: source, data: data, library: library)
        guard snapshot.originals == manifest.originals else { throw LibraryError.integrity("backup manifest") }
        return snapshot
    }

    /// Verify the selected backup's catalogue and the managed files relevant to an inspection.
    static func verifiedBackupOriginals(in source: URL, matching fingerprints: Set<String>) throws -> [Photo] {
        let (_, library, manifest) = try readBackupCatalogue(source)
        let managed = try library.uniqueOriginals().filter { $0.referencedPath == nil }
        let saved = Dictionary(uniqueKeysWithValues: managed.map { ($0.filename, $0.sha256) })
        guard saved == manifest.originals else { throw LibraryError.integrity("backup manifest") }
        let matches = managed.filter { fingerprints.contains($0.sha256) }
        for photo in matches {
            try Task.checkCancellation()
            let path = try LibraryRepository.managedOriginalURL(photo.filename, in: source)
            try LibraryRepository.verifyOriginal(path, photo: photo)
        }
        return matches
    }

    private static func readBackupCatalogue(_ source: URL) throws -> (Data, Library, Manifest) {
        let manifestURL = source.appendingPathComponent("backup-manifest.json")
        try regularFile(manifestURL)
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.version == 1 else { throw LibraryError.unsupportedVersion }
        let (data, library) = try readCatalogue(source)
        let fingerprint = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard fingerprint == manifest.catalogSHA256 else {
            throw LibraryError.integrity("backup catalogue")
        }
        return (data, library, manifest)
    }

    private static func copy(_ snapshot: Snapshot, from source: URL, to destination: URL, excluding current: URL?) throws {
        try publish(snapshot, to: destination, excluding: [source, current].compactMap { $0 }, writeManifest: true) { name in
            source.appendingPathComponent("Originals").appendingPathComponent(name)
        }
    }

    private static func publish(_ snapshot: Snapshot, to destination: URL, excluding protectedRoots: [URL],
                                writeManifest: Bool, originalURL: (String) throws -> URL) throws {
        try Task.checkCancellation()
        guard destination.isFileURL else { throw LibraryError.unsafePath }
        let fm = FileManager.default
        let proposed = destination.standardizedFileURL
        let parent = proposed.deletingLastPathComponent().resolvingSymlinksInPath()
        let target = parent.appendingPathComponent(proposed.lastPathComponent, isDirectory: true)
        let path = target.path.precomposedStringWithCanonicalMapping.lowercased()
        for protected in protectedRoots {
            let root = protected.resolvingSymlinksInPath().path.precomposedStringWithCanonicalMapping.lowercased()
            guard path != root, !path.hasPrefix(root + "/") else { throw LibraryError.unsafePath }
        }
        try LibraryRepository.validateRoot(target)
        guard !fm.fileExists(atPath: target.path),
              (try? target.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw LibraryError.unsafePath
        }
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: parent.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        guard fm.isWritableFile(atPath: parent.path) else { throw CocoaError(.fileWriteNoPermission) }
        let staging = parent.appendingPathComponent(".isonique-library-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: staging) }
        let originals = staging.appendingPathComponent("Originals", isDirectory: true)
        try fm.createDirectory(at: originals, withIntermediateDirectories: false)
        try snapshot.data.write(to: staging.appendingPathComponent("catalog.json"), options: .withoutOverwriting)
        for name in snapshot.originals.keys {
            try Task.checkCancellation()
            let source = try originalURL(name)
            try regularFile(source)
            try fm.copyItem(at: source, to: originals.appendingPathComponent(name))
        }
        let copied = try read(staging)
        guard copied.data == snapshot.data, copied.originals == snapshot.originals else { throw LibraryError.integrity("copied library") }
        if writeManifest {
            let manifest = Manifest(catalogSHA256: try LibraryRepository.digest(staging.appendingPathComponent("catalog.json")),
                                    originals: snapshot.originals)
            try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("backup-manifest.json"), options: .withoutOverwriting)
        }
        try Task.checkCancellation()
        try LibraryRepository.publishStagedItem(staging, at: target)
    }
}
