import Foundation

public enum OriginalStorage: String, Codable, CaseIterable, Identifiable {
    case managed = "Copy into library"
    case referenced = "Leave in current location"
    public var id: Self { self }
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
            updated.photos[index].referencedPath = input.path
            try save(updated)
            library = updated
        } else {
            try installManagedOriginal(from: input, photo: photo)
        }
    }

    /// Make a verified managed copy while leaving the external file in place.
    func consolidateOriginal(_ id: UUID, in library: inout Library) throws {
        guard let index = library.photos.firstIndex(where: { $0.id == id }),
              library.photos[index].referencedPath != nil else { throw LibraryError.unsafePath }
        let photo = library.photos[index]
        let input = try availableOriginalURL(photo)
        let copy = try installManagedOriginal(from: input, photo: photo)
        var updated = library
        updated.photos[index].referencedPath = nil
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
