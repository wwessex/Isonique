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
    let root: URL
    let catalogue: Data
}

public extension LibraryRepository {
    /// Check catalogue and storage metadata without opening, hashing or changing original files.
    func libraryFirstAidReport() throws -> LibraryFirstAidReport {
        let (catalogue, library) = try LibraryBackup.readCatalogue(root)
        let originals = try library.uniqueOriginals()
        let directory = root.appendingPathComponent("Originals", isDirectory: true)
        let managedFiles = try firstAidManagedFiles(in: directory)
        let caseSensitive = (try? directory.resourceValues(forKeys: [.volumeSupportsCaseSensitiveNamesKey])
            .volumeSupportsCaseSensitiveNames) == true
        func filenameKey(_ filename: String) -> String {
            caseSensitive ? filename : managedFilenameKey(filename)
        }
        var report = LibraryFirstAidReport(root: root, catalogue: catalogue)
        report.pendingFinderTrash = (library.pendingFinderTrash ?? []).map(\.filename)
        let knownNames = Set((originals.filter { $0.referencedPath == nil }.map(\.filename) + report.pendingFinderTrash)
            .map(filenameKey))

        for original in originals {
            try Task.checkCancellation()
            let item = LibraryFirstAidOriginal(id: original.originalID, name: original.originalName,
                                               location: original.referencedPath ?? directory.appendingPathComponent(original.filename).path)
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
        let library = try libraryForFirstAidRecovery(report)
        return try recoverMissingManagedOriginals(in: folder, library: library,
                                                   originalIDs: Set(report.missingManagedOriginals.map(\.id)),
                                                   expectedCatalogue: report.catalogue)
    }

    /// Relink only originals listed as offline, including versions in Library Trash.
    func reconnectOfflineReferences(in folder: URL, after report: LibraryFirstAidReport) throws
        -> (library: Library, report: OriginalReconnectReport) {
        var library = try libraryForFirstAidRecovery(report)
        let recovery = try reconnectMissingReferences(in: folder, library: &library,
                                                       originalIDs: Set(report.offlineReferences.map(\.id)),
                                                       includeTrashed: true, expectedCatalogue: report.catalogue)
        return (library, recovery)
    }

    private func libraryForFirstAidRecovery(_ report: LibraryFirstAidReport) throws -> Library {
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

    private func firstAidManagedFiles(in directory: URL) throws -> [URL] {
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
