import Darwin
import Foundation

// Default Mac volumes can resolve different spellings to the same directory entry.
func managedFilenameKey(_ filename: String) -> String {
    filename.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        .precomposedStringWithCanonicalMapping
}

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

public struct ManagedOriginalRecoveryReport: Sendable {
    public fileprivate(set) var restored: [String] = []
    public fileprivate(set) var unmatched: [String] = []
    public fileprivate(set) var ambiguous: [String] = []
    public fileprivate(set) var occupied: [String] = []
    public fileprivate(set) var failed: [String] = []
    public fileprivate(set) var scanErrors = 0
    public fileprivate(set) var cancelled = false
}

public struct OriginalConsolidationReport: Sendable {
    public fileprivate(set) var consolidated: [String] = []
    public fileprivate(set) var unavailable: [String] = []
    public fileprivate(set) var occupied: [String] = []
    public fileprivate(set) var failed: [String] = []
    public fileprivate(set) var cancelled = false
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
    func reconnectMissingReferences(in folder: URL, library: inout Library,
                                    originalIDs: Set<UUID>? = nil) throws -> OriginalReconnectReport {
        try Task.checkCancellation()
        let activeOriginalIDs = Set(library.activePhotos.map(\.originalID))
        let missing = try library.uniqueOriginals().filter { photo in
            photo.referencedPath != nil && activeOriginalIDs.contains(photo.originalID) &&
                originalIDs?.contains(photo.originalID) != false &&
                (try? availableOriginalURL(photo)) == nil
        }
        var report = OriginalReconnectReport()
        let matches = try originalMatches(in: folder, for: missing, includeStoredName: false, scanErrors: &report.scanErrors)

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

    /// Restore exact copies at the existing managed paths. Each file is installed independently.
    func recoverMissingManagedOriginals(in folder: URL, library: Library,
                                        originalIDs: Set<UUID>? = nil) throws -> ManagedOriginalRecoveryReport {
        try Task.checkCancellation()
        var report = ManagedOriginalRecoveryReport()
        var missing: [Photo] = []
        for photo in try library.uniqueOriginals() where photo.referencedPath == nil {
            guard originalIDs?.contains(photo.originalID) != false else { continue }
            try Task.checkCancellation()
            guard (try? availableOriginalURL(photo)) == nil else { continue }
            if let target = try? managedOriginalURL(photo.filename), !FileManager.default.fileExists(atPath: target.path) {
                missing.append(photo)
            } else {
                report.occupied.append(photo.originalName)
            }
        }
        let matches = try originalMatches(in: folder, for: missing, includeStoredName: true, scanErrors: &report.scanErrors)
        for photo in missing {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            let candidates = matches[photo.originalID] ?? []
            if candidates.count > 1 {
                report.ambiguous.append(photo.originalName)
            } else if let candidate = candidates.first {
                do {
                    let verified = try Self.referenceURL(candidate.path, libraryRoot: root)
                    try installManagedOriginal(from: verified, photo: photo)
                    report.restored.append(photo.originalName)
                } catch is CancellationError {
                    report.cancelled = true
                    break
                } catch {
                    if let target = try? managedOriginalURL(photo.filename),
                       !FileManager.default.fileExists(atPath: target.path) {
                        report.failed.append(photo.originalName)
                    } else {
                        report.occupied.append(photo.originalName)
                    }
                }
            } else {
                report.unmatched.append(photo.originalName)
            }
        }
        return report
    }

    private func originalMatches(in folder: URL, for originals: [Photo], includeStoredName: Bool,
                                 scanErrors: inout Int) throws -> [UUID: [URL]] {
        guard folder.isFileURL else { throw LibraryError.unsafePath }
        let directory = try Self.referenceURL(folder.path, libraryRoot: root)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey]
        guard try directory.resourceValues(forKeys: keys).isDirectory == true else { throw LibraryError.unsafePath }
        guard !originals.isEmpty else { return [:] }

        func filenameKey(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }
        var originalsByName: [String: [Photo]] = [:]
        for photo in originals {
            let names = [photo.referencedPath.map { URL(fileURLWithPath: $0).lastPathComponent },
                         photo.sourceName, photo.originalName, includeStoredName ? photo.filename : nil]
            for name in Set(names.compactMap { $0.map(filenameKey) }) {
                originalsByName[name, default: []].append(photo)
            }
        }

        var errors = 0
        guard let files = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in errors += 1; return true }
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
                try Task.checkCancellation()
                errors += 1
            }
        }
        scanErrors += errors
        return matches
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

    /// Copy selected originals and publish their managed paths together.
    func consolidateOriginals(_ originalIDs: Set<UUID>, in library: inout Library) throws -> OriginalConsolidationReport {
        let catalogue = root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let originals = try library.uniqueOriginals().filter { $0.referencedPath != nil && originalIDs.contains($0.originalID) }
        var report = OriginalConsolidationReport()
        var completed: Set<UUID> = []
        for photo in originals {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            guard let input = try? availableOriginalURL(photo) else {
                report.unavailable.append(photo.originalName)
                continue
            }
            guard let target = try? managedOriginalURL(photo.filename) else {
                report.occupied.append(photo.originalName)
                continue
            }
            do {
                if FileManager.default.fileExists(atPath: target.path) {
                    // A previous run may have copied the bytes before saving the catalogue.
                    try Self.verifyOriginal(input, photo: photo)
                    guard (try? Self.verifyOriginal(target, photo: photo)) != nil else {
                        report.occupied.append(photo.originalName)
                        continue
                    }
                    try Task.checkCancellation()
                } else {
                    try installManagedOriginal(from: input, photo: photo)
                }
                completed.insert(photo.originalID)
                report.consolidated.append(photo.originalName)
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.failed.append(photo.originalName)
            }
        }
        guard !completed.isEmpty else { return report }

        var updated = library
        for index in updated.photos.indices where completed.contains(updated.photos[index].originalID) {
            updated.photos[index].referencedPath = nil
        }
        // Keep exact copies if saving fails. A retry can verify and reuse them.
        guard try Data(contentsOf: catalogue) == before else { throw LibraryError.integrity("catalogue changed during consolidation") }
        try save(updated)
        library = updated
        return report
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

    internal static func verifyOriginal(_ url: URL, photo: Photo) throws {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw LibraryError.originalUnavailable(photo.originalName)
        }
        guard try digest(url) == photo.sha256 else { throw LibraryError.integrity(photo.originalName) }
    }

    @discardableResult
    private func installManagedOriginal(from input: URL, photo: Photo) throws -> URL {
        let target = try managedOriginalURL(photo.filename)
        try Self.installVerifiedOriginal(from: input, at: target, photo: photo)
        return target
    }

    internal static func installVerifiedOriginal(from input: URL, at target: URL, photo: Photo) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: target.path) else { throw LibraryError.unsafePath }
        try verifyOriginal(input, photo: photo)
        let staging = target.deletingLastPathComponent().appendingPathComponent(".isonique-original-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: input, to: staging)
        try verifyOriginal(staging, photo: photo)
        try Task.checkCancellation()
        try publishStagedItem(staging, at: target)
    }

    internal static func publishStagedItem(_ staging: URL, at target: URL) throws {
        // A competing writer cannot replace an occupied path.
        try staging.withUnsafeFileSystemRepresentation { stagedPath in
            try target.withUnsafeFileSystemRepresentation { targetPath in
                guard let stagedPath, let targetPath else { throw LibraryError.unsafePath }
                guard renamex_np(stagedPath, targetPath, UInt32(RENAME_EXCL)) == 0 else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
            }
        }
    }
}
