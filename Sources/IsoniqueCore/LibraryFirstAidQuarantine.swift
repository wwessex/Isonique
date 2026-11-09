import Foundation
import Darwin

public struct LibraryFirstAidQuarantinedFile: Sendable {
    public let filename: String
    public let sha256: String
}

public struct LibraryFirstAidRestoreReview: Sendable {
    public let files: [LibraryFirstAidQuarantinedFile]
    public let unavailableFiles: [String]
    let root: URL
}

public struct LibraryFirstAidMoveResult: Sendable {
    public fileprivate(set) var moved: [String] = []
    public fileprivate(set) var claimed: [String] = []
    public fileprivate(set) var changedOrUnavailable: [String] = []
    public fileprivate(set) var occupied: [String] = []
    public fileprivate(set) var failures: [String] = []
    public fileprivate(set) var cancelled = false
}

public extension LibraryRepository {
    /// Move inspected files into the library's quarantine using current catalogue ownership.
    func quarantineUntrackedManagedFiles(after review: LibraryFirstAidInspection) throws -> LibraryFirstAidMoveResult {
        guard review.root == root else { throw LibraryError.unsafePath }
        let files = review.files.map { LibraryFirstAidQuarantinedFile(filename: $0.filename, sha256: $0.sha256) }
        return try moveFirstAidFiles(files, restoring: false)
    }

    /// Read the fingerprints of files currently in quarantine for a restore review.
    func reviewQuarantinedManagedFiles() throws -> LibraryFirstAidRestoreReview {
        var reviewed: [LibraryFirstAidQuarantinedFile] = []
        var unavailable: [String] = []
        for name in try quarantinedFileNames() {
            try Task.checkCancellation()
            do {
                let file = try quarantineFileURL(name)
                try LibraryBackup.regularFile(file)
                reviewed.append(LibraryFirstAidQuarantinedFile(filename: name, sha256: try Self.digest(file)))
            } catch {
                unavailable.append(name)
            }
        }
        return LibraryFirstAidRestoreReview(files: reviewed, unavailableFiles: unavailable, root: root)
    }

    /// Return reviewed files to their original names in Originals.
    func restoreQuarantinedManagedFiles(after review: LibraryFirstAidRestoreReview) throws -> LibraryFirstAidMoveResult {
        guard review.root == root else { throw LibraryError.unsafePath }
        return try moveFirstAidFiles(review.files, restoring: true)
    }

    internal func quarantinedFileNames() throws -> [String] {
        try firstAidFiles(in: quarantineDirectory).compactMap { file in
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            return values.isRegularFile == true && values.isSymbolicLink != true ? file.lastPathComponent : nil
        }.sorted()
    }

    private var quarantineDirectory: URL {
        root.appendingPathComponent("First Aid Quarantine", isDirectory: true)
    }

    private func quarantineFileURL(_ filename: String) throws -> URL {
        guard !filename.isEmpty, filename != ".", filename != "..",
              filename == (filename as NSString).lastPathComponent else { throw LibraryError.unsafePath }
        let folder = quarantineDirectory
        let path = folder.appendingPathComponent(filename)
        guard folder.resolvingSymlinksInPath().path == folder.path,
              path.resolvingSymlinksInPath().path == path.path,
              (try? path.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw LibraryError.unsafePath
        }
        return path
    }

    private func moveFirstAidFiles(_ files: [LibraryFirstAidQuarantinedFile], restoring: Bool) throws
        -> LibraryFirstAidMoveResult {
        try Task.checkCancellation()
        return try withCatalogueWriteLock {
            let (_, library) = try LibraryBackup.readCatalogue(root)
            let originals = try library.uniqueOriginals()
            let managedDirectory = root.appendingPathComponent("Originals").path
            let claimed = originals.compactMap { photo -> String? in
                guard let reference = photo.referencedPath else { return photo.filename }
                let path = URL(fileURLWithPath: reference).resolvingSymlinksInPath()
                return path.deletingLastPathComponent().path == managedDirectory ? path.lastPathComponent : nil
            }
            let pending = (library.pendingFinderTrash ?? []).map(\.filename)
            let protectedNames = Set((claimed + pending).map(managedFilenameKey))
            var result = LibraryFirstAidMoveResult()
            for file in files {
                if Task.isCancelled {
                    result.cancelled = true
                    break
                }
                if protectedNames.contains(managedFilenameKey(file.filename)) {
                    result.claimed.append(file.filename)
                    continue
                }
                let source: URL
                let destination: URL
                do {
                    let managed = try managedOriginalURL(file.filename)
                    let quarantined = try quarantineFileURL(file.filename)
                    source = restoring ? quarantined : managed
                    destination = restoring ? managed : quarantined
                    try LibraryBackup.regularFile(source)
                    guard try Self.digest(source) == file.sha256 else { throw LibraryError.integrity(file.filename) }
                } catch {
                    result.changedOrUnavailable.append(file.filename)
                    continue
                }
                do {
                    if !restoring {
                        try FileManager.default.createDirectory(at: quarantineDirectory, withIntermediateDirectories: true)
                        _ = try quarantineFileURL(file.filename)
                    }
                    try Self.publishStagedItem(source, at: destination)
                    result.moved.append(file.filename)
                } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(EEXIST) {
                    result.occupied.append(file.filename)
                } catch {
                    result.failures.append("\(file.filename) — \(error.localizedDescription)")
                }
            }
            return result
        }
    }
}
