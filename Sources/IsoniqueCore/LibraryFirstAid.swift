import Foundation

public struct LibraryFirstAidOriginal: Sendable {
    public let id: UUID
    public let name: String
    public let location: String
}

public struct LibraryFirstAidReport: Sendable {
    public fileprivate(set) var missingManagedOriginals: [LibraryFirstAidOriginal] = []
    public fileprivate(set) var offlineReferences: [LibraryFirstAidOriginal] = []
    public fileprivate(set) var untrackedManagedFiles: [String] = []
    public fileprivate(set) var originalsRequiringInspection: [LibraryFirstAidOriginal] = []
    public fileprivate(set) var pendingFinderTrash: [String] = []
    public fileprivate(set) var quarantinedFiles: [String] = []
    let root: URL
    let catalogue: Data
}

public struct LibraryFirstAidBackupMatch: Sendable {
    public let backup: URL
    public let original: LibraryFirstAidOriginal
}

public struct LibraryFirstAidInspectedFile: Sendable {
    public let filename: String
    public let sha256: String
    public let catalogueMatches: [LibraryFirstAidOriginal]
    public let backupMatches: [LibraryFirstAidBackupMatch]
}

public struct LibraryFirstAidInspection: Sendable {
    public let files: [LibraryFirstAidInspectedFile]
    public let unavailableFiles: [String]
    let root: URL
}

public extension LibraryRepository {
    /// Check catalogue and storage metadata without opening, hashing or changing original files.
    func libraryFirstAidReport() throws -> LibraryFirstAidReport {
        let (catalogue, library) = try LibraryBackup.readCatalogue(root)
        let originals = try library.uniqueOriginals()
        let directory = root.appendingPathComponent("Originals", isDirectory: true)
        let managedFiles = try firstAidFiles(in: directory)
        let caseSensitive = (try? directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames) == true
        func filenameKey(_ filename: String) -> String {
            caseSensitive ? filename : managedFilenameKey(filename)
        }
        var report = LibraryFirstAidReport(root: root, catalogue: catalogue)
        report.pendingFinderTrash = (library.pendingFinderTrash ?? []).map(\.filename)
        report.quarantinedFiles = try quarantinedFileNames()
        let knownNames = Set((originals.filter { $0.referencedPath == nil }.map(\.filename) + report.pendingFinderTrash)
            .map(filenameKey))

        for original in originals {
            try Task.checkCancellation()
            let item = firstAidOriginal(original, in: root)
            do {
                try LibraryBackup.regularFile(originalURL(original))
            } catch let error as CocoaError where error.isMissingFirstAidPath {
                if original.referencedPath == nil { report.missingManagedOriginals.append(item) }
                else { report.offlineReferences.append(item) }
            } catch {
                report.originalsRequiringInspection.append(item)
            }
        }
        for file in managedFiles where !knownNames.contains(filenameKey(file.lastPathComponent)) {
            try Task.checkCancellation()
            do {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                if values.isRegularFile == true, values.isSymbolicLink != true {
                    report.untrackedManagedFiles.append(file.lastPathComponent)
                }
            } catch let error as CocoaError where error.isMissingFirstAidPath {
                continue
            }
        }
        report.untrackedManagedFiles.sort()
        try checkFirstAidCatalogue(catalogue)
        return report
    }

    /// Restore only managed originals listed as missing in the reviewed report.
    func recoverMissingManagedOriginals(in folder: URL, after report: LibraryFirstAidReport) throws
        -> ManagedOriginalRecoveryReport {
        let library = try libraryForFirstAidAction(report)
        return try recoverMissingManagedOriginals(in: folder, library: library,
                                                   originalIDs: Set(report.missingManagedOriginals.map(\.id)),
                                                   expectedCatalogue: report.catalogue)
    }

    /// Relink only originals listed as offline, including versions in Library Trash.
    func reconnectOfflineReferences(in folder: URL, after report: LibraryFirstAidReport) throws
        -> (library: Library, report: OriginalReconnectReport) {
        var library = try libraryForFirstAidAction(report)
        let recovery = try reconnectMissingReferences(in: folder, library: &library,
                                                       originalIDs: Set(report.offlineReferences.map(\.id)),
                                                       includeTrashed: true, expectedCatalogue: report.catalogue)
        return (library, recovery)
    }

    /// Identify reviewed untracked files by their contents and leave all libraries in place.
    func inspectUntrackedManagedFiles(after report: LibraryFirstAidReport, backups: [URL] = []) throws
        -> LibraryFirstAidInspection {
        let library = try libraryForFirstAidAction(report)
        let originals = Dictionary(grouping: try library.uniqueOriginals(), by: \.sha256)
        var files: [(filename: String, sha256: String)] = []
        var unavailable: [String] = []
        for name in report.untrackedManagedFiles {
            try Task.checkCancellation()
            do {
                let path = try managedOriginalURL(name)
                try LibraryBackup.regularFile(path)
                files.append((name, try Self.digest(path)))
            } catch {
                unavailable.append(name)
            }
        }

        let fingerprints = Set(files.map(\.sha256))
        var matchedBackups: [String: [LibraryFirstAidBackupMatch]] = [:]
        var inspectedBackups: Set<URL> = []
        for backup in backups {
            try Task.checkCancellation()
            guard backup.isFileURL else { throw LibraryError.unsafePath }
            let folder = backup.standardizedFileURL.resolvingSymlinksInPath()
            guard inspectedBackups.insert(folder).inserted else { continue }
            for photo in try LibraryBackup.verifiedBackupOriginals(in: folder, matching: fingerprints) {
                let item = firstAidOriginal(photo, in: folder)
                matchedBackups[photo.sha256, default: []].append(LibraryFirstAidBackupMatch(backup: folder, original: item))
            }
        }

        let inspected = files.map { file in
            LibraryFirstAidInspectedFile(filename: file.filename, sha256: file.sha256,
                                         catalogueMatches: (originals[file.sha256] ?? []).map { firstAidOriginal($0, in: root) },
                                         backupMatches: matchedBackups[file.sha256] ?? [])
        }
        try checkFirstAidCatalogue(report.catalogue)
        return LibraryFirstAidInspection(files: inspected, unavailableFiles: unavailable, root: root)
    }

    private func firstAidOriginal(_ photo: Photo, in library: URL) -> LibraryFirstAidOriginal {
        LibraryFirstAidOriginal(id: photo.originalID, name: photo.originalName,
                               location: photo.referencedPath ?? library.appendingPathComponent("Originals")
                                .appendingPathComponent(photo.filename).path)
    }

    private func libraryForFirstAidAction(_ report: LibraryFirstAidReport) throws -> Library {
        guard report.root == root else { throw LibraryError.unsafePath }
        let (catalogue, library) = try LibraryBackup.readCatalogue(root)
        guard catalogue == report.catalogue else {
            throw LibraryError.integrity("catalogue changed since the Library First Aid report; run it again")
        }
        return library
    }

    internal func checkFirstAidCatalogue(_ expected: Data) throws {
        let url = root.appendingPathComponent("catalog.json")
        try LibraryBackup.regularFile(url)
        guard try Data(contentsOf: url) == expected else {
            throw LibraryError.integrity("catalogue changed since the Library First Aid report; run it again")
        }
    }

    internal func firstAidFiles(in directory: URL) throws -> [URL] {
        do {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw LibraryError.unsafePath }
            return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        } catch let error as CocoaError where error.isMissingFirstAidPath {
            return []
        }
    }
}

private extension CocoaError {
    var isMissingFirstAidPath: Bool { code == .fileNoSuchFile || code == .fileReadNoSuchFile }
}
