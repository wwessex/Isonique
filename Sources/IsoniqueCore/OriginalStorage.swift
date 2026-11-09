import Foundation

public enum OriginalStorage: String, Codable, CaseIterable, Identifiable {
    case managed = "Copy into library"
    case referenced = "Leave in current location"
    public var id: Self { self }
}

public struct OriginalReconnectReport: Sendable {
    public fileprivate(set) var reconnected: [String] = []
    public fileprivate(set) var unmatched: [String] = []
    public fileprivate(set) var ambiguous: [String] = []
    public fileprivate(set) var scanErrors = 0
}

public extension LibraryRepository {
    func availableOriginalURL(_ photo: Photo) throws -> URL {
        let url = try originalURL(photo)
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw LibraryError.originalUnavailable(photo.originalName)
        }
        return url
    }

    /// Reconnect a reference or restore a missing managed copy from the same original bytes.
    func relinkOriginal(_ id: UUID, to source: URL, in library: inout Library) throws {
        guard let index = library.photos.firstIndex(where: { $0.id == id }) else { throw LibraryError.unsafePath }
        let photo = library.photos[index]
        guard source.isFileURL else { throw LibraryError.unsafePath }
        let input = try Self.referenceURL(source.path, libraryRoot: root)
        if photo.referencedPath != nil {
            try Self.verifyOriginal(input, photo: photo)
            var updated = library
            for index in updated.photos.indices where updated.photos[index].originalID == photo.originalID {
                updated.photos[index].referencedPath = input.path
            }
            try save(updated)
            library = updated
        } else {
            try installManagedOriginal(from: input, photo: photo)
        }
    }

    /// Reconnect missing references by known filenames and verified fingerprints.
    func reconnectMissingReferences(in folder: URL, library: inout Library) throws -> OriginalReconnectReport {
        try Task.checkCancellation()
        guard folder.isFileURL else { throw LibraryError.unsafePath }
        let directory = try Self.referenceURL(folder.path, libraryRoot: root)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard try directory.resourceValues(forKeys: keys).isDirectory == true else { throw LibraryError.unsafePath }

        let activeOriginalIDs = Set(library.activePhotos.map(\.originalID))
        let missing = try library.uniqueOriginals().filter { photo in
            photo.referencedPath != nil && activeOriginalIDs.contains(photo.originalID) &&
                (try? availableOriginalURL(photo)) == nil
        }
        var report = OriginalReconnectReport()
        guard !missing.isEmpty else { return report }

        func filenameKey(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }
        var originalsByName: [String: [Photo]] = [:]
        for photo in missing {
            let names = [photo.referencedPath.map { URL(fileURLWithPath: $0).lastPathComponent },
                         photo.sourceName, photo.originalName]
            for name in Set(names.compactMap { $0.map(filenameKey) }) {
                originalsByName[name, default: []].append(photo)
            }
        }

        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in report.scanErrors += 1; return true }
        ) else { throw LibraryError.unsafePath }
        var matches: [UUID: [URL]] = [:]
        for case let url as URL in files {
            try Task.checkCancellation()
            if url.path == root.path { files.skipDescendants(); continue }
            guard let possible = originalsByName[filenameKey(url.lastPathComponent)] else { continue }
            do {
                let values = try url.resourceValues(forKeys: keys)
                guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
                let candidate = try Self.referenceURL(url.path, libraryRoot: root)
                let fingerprint = try Self.digest(candidate)
                for photo in possible where photo.sha256 == fingerprint {
                    if matches[photo.originalID, default: []].count < 2 {
                        matches[photo.originalID, default: []].append(candidate)
                    }
                }
            } catch {
                report.scanErrors += 1
            }
        }

        var paths: [UUID: String] = [:]
        for photo in missing {
            try Task.checkCancellation()
            guard (try? availableOriginalURL(photo)) == nil else { continue }
            let candidates = matches[photo.originalID] ?? []
            if candidates.count > 1 {
                report.ambiguous.append(photo.originalName)
            } else if let candidate = candidates.first {
                let verified = try Self.referenceURL(candidate.path, libraryRoot: root)
                try Self.verifyOriginal(verified, photo: photo)
                paths[photo.originalID] = verified.path
                report.reconnected.append(photo.originalName)
            } else {
                report.unmatched.append(photo.originalName)
            }
        }
        guard !paths.isEmpty else { return report }
        var updated = library
        for index in updated.photos.indices {
            if let path = paths[updated.photos[index].originalID] { updated.photos[index].referencedPath = path }
        }
        try Task.checkCancellation()
        try save(updated)
        library = updated
        return report
    }

    /// Make a verified managed copy while leaving the external file in place.
    func consolidateOriginal(_ id: UUID, in library: inout Library) throws {
        guard let index = library.photos.firstIndex(where: { $0.id == id }),
              library.photos[index].referencedPath != nil else { throw LibraryError.unsafePath }
        let photo = library.photos[index]
        let input = try availableOriginalURL(photo)
        let copy = try installManagedOriginal(from: input, photo: photo)
        var updated = library
        for index in updated.photos.indices where updated.photos[index].originalID == photo.originalID {
            updated.photos[index].referencedPath = nil
        }
        do { try save(updated) } catch {
            try? FileManager.default.removeItem(at: copy)
            throw error
        }
        library = updated
    }

    internal static func referenceURL(_ path: String, libraryRoot: URL) throws -> URL {
        guard path.hasPrefix("/") else { throw LibraryError.unsafePath }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path != libraryRoot.path, !url.path.hasPrefix(libraryRoot.path + "/") else {
            throw LibraryError.unsafePath
        }
        try validateRoot(url)
        return url
    }

    private static func verifyOriginal(_ url: URL, photo: Photo) throws {
        guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            throw LibraryError.originalUnavailable(photo.originalName)
        }
        guard try digest(url) == photo.sha256 else { throw LibraryError.integrity(photo.originalName) }
    }

    @discardableResult
    private func installManagedOriginal(from input: URL, photo: Photo) throws -> URL {
        let fm = FileManager.default
        let target = try managedOriginalURL(photo.filename)
        guard !fm.fileExists(atPath: target.path) else { throw LibraryError.unsafePath }
        try Self.verifyOriginal(input, photo: photo)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".isonique-original-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: input, to: staging)
        try Self.verifyOriginal(staging, photo: photo)
        try fm.moveItem(at: staging, to: target)
        return target
    }
}
