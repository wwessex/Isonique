import Darwin
import Foundation

public enum OriginalRelocationFilename: String, CaseIterable, Sendable {
    case original = "Original filename"
    case catalogue = "Catalogue filename"
    case sequence = "Numbered sequence"
}

public enum OriginalRelocationSubfolders: String, CaseIterable, Sendable {
    case none = "No subfolders"
    case project = "Project name"
    case captureMonth = "Capture year / month"
}

public struct OriginalRelocationOptions: Sendable {
    public var filename: OriginalRelocationFilename
    public var subfolders: OriginalRelocationSubfolders
    public var keepReferencedSources: Bool

    public init(filename: OriginalRelocationFilename = .original, subfolders: OriginalRelocationSubfolders = .none,
                keepReferencedSources: Bool = true) {
        self.filename = filename
        self.subfolders = subfolders
        self.keepReferencedSources = keepReferencedSources
    }
}

public struct OriginalRelocationItem: Sendable {
    public enum Disposition: Sendable { case copy, reuse, alreadyThere, unavailable, occupied }
    public let originalID: UUID
    public let originalName: String
    public let versionCount: Int
    public let preferredPath: String
    public let destinationPath: String?
    public let disposition: Disposition
    public var willRelocate: Bool { disposition == .copy || disposition == .reuse }
}

public struct OriginalRelocationPreview: Sendable {
    public let destination: URL
    public var items: [OriginalRelocationItem] { entries.map(\.item) }
    public var relocationCount: Int { entries.reduce(0) { $0 + ($1.item.willRelocate ? 1 : 0) } }
    fileprivate let root: URL
    fileprivate let catalogue: Data
    fileprivate let options: OriginalRelocationOptions
    fileprivate let entries: [OriginalRelocationEntry]
}

private struct OriginalRelocationEntry: Sendable {
    let item: OriginalRelocationItem
    let sourceFilename: String
    let source: URL?
    let folders: [String]
}

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
    /// Plan one destination per original without creating folders, copying files or changing the catalogue.
    func previewRelocatingOriginals(_ originalIDs: Set<UUID>, to folder: URL, in library: Library,
                                   options: OriginalRelocationOptions = .init()) throws -> OriginalRelocationPreview {
        try Task.checkCancellation()
        guard folder.isFileURL else { throw LibraryError.unsafePath }
        let directory = try Self.referenceURL(folder.path, libraryRoot: root)
        try checkRelocationRoot(directory)

        let catalogue = try relocationCatalogue()
        try checkRelocationBase(library, catalogue: catalogue)
        let allOriginals = try library.uniqueOriginals()
        let originals = allOriginals.filter { originalIDs.contains($0.originalID) }
        let referencedPaths = Set(allOriginals.compactMap { $0.referencedPath.map(relocationPathKey) })
        let versionCounts = library.photos.reduce(into: [UUID: Int]()) { $0[$1.originalID, default: 0] += 1 }
        let projects = Dictionary(library.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { name, _ in name })
        var reserved: Set<String> = []
        var entries: [OriginalRelocationEntry] = []
        for (index, photo) in originals.enumerated() {
            try Task.checkCancellation()
            let source = try? availableOriginalURL(photo)
            let originalName = relocationName(for: photo, source: source)
            let folders = relocationFolders(for: photo, preset: options.subfolders, projects: projects)
            let name = relocationFilename(for: photo, originalName: originalName, index: index, preset: options.filename)
            let preferred = (folders + [name]).joined(separator: "/")
            func entry(_ disposition: OriginalRelocationItem.Disposition, destination: String? = nil) -> OriginalRelocationEntry {
                OriginalRelocationEntry(item: OriginalRelocationItem(
                    originalID: photo.originalID, originalName: photo.originalName, versionCount: versionCounts[photo.originalID, default: 1],
                    preferredPath: preferred, destinationPath: destination, disposition: disposition),
                    sourceFilename: originalName, source: source, folders: folders)
            }
            guard let source else { entries.append(entry(.unavailable)); continue }
            guard let parent = try? relocationParent(in: directory, folders: folders, create: false) else {
                entries.append(entry(.occupied)); continue
            }
            var choice: OriginalRelocationEntry?
            for candidate in (name == photo.filename ? [name] : [name, photo.filename]) where safeRelocationComponent(candidate) {
                let target = parent.appendingPathComponent(candidate)
                let relative = (folders + [candidate]).joined(separator: "/")
                if photo.referencedPath != nil, candidate == source.lastPathComponent,
                   sameRelocationDirectory(source.deletingLastPathComponent(), parent) {
                    choice = entry(.alreadyThere, destination: relative)
                    break
                }
                let key = managedFilenameKey(target.path)
                guard !reserved.contains(key), !referencedPaths.contains(key) else { continue }
                switch try? relocationNode(at: target) {
                case .missing: choice = entry(.copy, destination: relative)
                case .file where (try? Self.verifyOriginal(target, photo: photo)) != nil:
                    choice = entry(.reuse, destination: relative)
                default: continue
                }
                reserved.insert(key)
                break
            }
            entries.append(choice ?? entry(.occupied))
        }
        guard try relocationCatalogue() == catalogue else { throw LibraryError.staleCatalogue }
        return OriginalRelocationPreview(destination: directory, root: root, catalogue: catalogue, options: options, entries: entries)
    }

    /// Copy only to the reviewed paths, save all versions' references, then release eligible sources.
    func relocateOriginals(after preview: OriginalRelocationPreview, in library: inout Library) throws -> OriginalRelocationReport {
        try relocateOriginals(after: preview, in: &library) { source in
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
        }
    }

    func relocateOriginals(_ originalIDs: Set<UUID>, to folder: URL, in library: inout Library,
                           keepReferencedSources: Bool = true) throws -> OriginalRelocationReport {
        let review = try previewRelocatingOriginals(originalIDs, to: folder, in: library,
                                                   options: .init(keepReferencedSources: keepReferencedSources))
        return try relocateOriginals(after: review, in: &library)
    }

    internal func relocateOriginals(_ originalIDs: Set<UUID>, to folder: URL, in library: inout Library,
                                    keepReferencedSources: Bool = true, trashSource: (URL) throws -> Void) throws -> OriginalRelocationReport {
        let review = try previewRelocatingOriginals(originalIDs, to: folder, in: library,
                                                   options: .init(keepReferencedSources: keepReferencedSources))
        return try relocateOriginals(after: review, in: &library, trashSource: trashSource)
    }

    internal func relocateOriginals(after preview: OriginalRelocationPreview, in library: inout Library,
                                    trashSource: (URL) throws -> Void) throws -> OriginalRelocationReport {
        try Task.checkCancellation()
        guard preview.root == root else { throw LibraryError.unsafePath }
        try checkRelocationRoot(preview.destination)
        try checkReviewedRelocation(preview, library: library)

        var report = OriginalRelocationReport()
        let originals = Dictionary(uniqueKeysWithValues: try library.uniqueOriginals().map { ($0.originalID, $0) })
        var transfers: [(entry: OriginalRelocationEntry, photo: Photo, source: URL, target: URL)] = []
        for entry in preview.entries {
            try Task.checkCancellation()
            let item = entry.item
            switch item.disposition {
            case .unavailable: report.unavailable.append(item.originalName); continue
            case .alreadyThere: report.alreadyInFolder.append(item.originalName); continue
            case .occupied: report.occupied.append(item.originalName); continue
            case .copy, .reuse: break
            }
            guard let source = entry.source, let relative = item.destinationPath, let photo = originals[item.originalID] else {
                throw LibraryError.staleCatalogue
            }
            do {
                guard try availableOriginalURL(photo).path == source.path else { throw LibraryError.staleCatalogue }
                let target = preview.destination.appendingPathComponent(relative)
                _ = try relocationParent(in: preview.destination, folders: entry.folders, create: false)
                switch try relocationNode(at: target) {
                case .missing where item.disposition == .copy:
                    _ = try relocationParent(in: preview.destination, folders: entry.folders, create: true)
                    try Self.installVerifiedOriginal(from: source, at: target, photo: photo)
                case .file where item.disposition == .reuse:
                    try Self.verifyOriginal(target, photo: photo)
                    try Self.verifyOriginal(source, photo: photo)
                default:
                    // Keep the reviewed path fixed; a fresh preview can offer a different one.
                    report.occupied.append(relative)
                    continue
                }
                transfers.append((entry, photo, source, target))
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                report.failed.append(relative)
            }
        }
        guard !transfers.isEmpty else { return report }

        try Task.checkCancellation()
        return try withCatalogueWriteLock {
            try checkReviewedRelocation(preview, library: library)
            var paths: [UUID: String] = [:]
            for transfer in transfers {
                try Task.checkCancellation()
                _ = try relocationParent(in: preview.destination, folders: transfer.entry.folders, create: false)
                let resolved = try Self.referenceURL(transfer.target.path, libraryRoot: root)
                guard resolved.path == transfer.target.path else { throw LibraryError.unsafePath }
                try Self.verifyOriginal(resolved, photo: transfer.photo)
                paths[transfer.photo.originalID] = resolved.path
            }
            var updated = library
            updated.version = max(updated.version, 2)
            for index in updated.photos.indices {
                if let path = paths[updated.photos[index].originalID] { updated.photos[index].referencedPath = path }
            }
            // Include unselected and trashed records, and hold the write lock through cleanup.
            let managedDirectory = root.appendingPathComponent("Originals")
            let claimedPaths = Set(try updated.uniqueOriginals().map { photo in
                relocationPathKey(photo.referencedPath ?? managedDirectory.appendingPathComponent(photo.filename).path)
            })
            try Task.checkCancellation()
            library = try writeCatalogue(updated)

            var released: Set<String> = []
            for transfer in transfers {
                let photo = transfer.photo
                let source = transfer.source
                report.relocated.append(photo.originalName)
                if transfer.target.lastPathComponent != transfer.entry.sourceFilename {
                    report.renamed.append(transfer.target.lastPathComponent)
                }
                let key = relocationPathKey(source.path)
                if claimedPaths.contains(key) || (photo.referencedPath != nil && preview.options.keepReferencedSources) {
                    report.retained.append(photo.originalName)
                    continue
                }
                if released.contains(key) { continue }
                do {
                    try Task.checkCancellation()
                    _ = try relocationParent(in: preview.destination, folders: transfer.entry.folders, create: false)
                    try Self.verifyOriginal(transfer.target, photo: photo)
                    try Self.verifyOriginal(source, photo: photo)
                    try trashSource(source)
                    released.insert(key)
                } catch {
                    report.retained.append(photo.originalName)
                }
            }
            return report
        }
    }

    private func relocationCatalogue() throws -> Data {
        let catalogue = root.appendingPathComponent("catalog.json")
        try LibraryBackup.regularFile(catalogue)
        return try Data(contentsOf: catalogue)
    }

    private func checkReviewedRelocation(_ preview: OriginalRelocationPreview, library: Library) throws {
        guard try relocationCatalogue() == preview.catalogue else {
            throw LibraryError.integrity("the catalogue changed since the relocation preview; reload the library and review again")
        }
        try checkRelocationBase(library, catalogue: preview.catalogue)
    }

    private func checkRelocationBase(_ library: Library, catalogue: Data) throws {
        if let expected = library.catalogueRevision, expected != CatalogueRevision(catalogue) {
            throw LibraryError.staleCatalogue
        }
    }

    private func relocationPathKey(_ path: String) -> String {
        managedFilenameKey(URL(fileURLWithPath: path).resolvingSymlinksInPath().path)
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

    private func checkRelocationRoot(_ directory: URL) throws {
        let key = managedFilenameKey(directory.path)
        let library = managedFilenameKey(root.path)
        guard key != library, !key.hasPrefix(library + "/"),
              directory.resolvingSymlinksInPath().path == directory.path,
              try relocationNode(at: directory) == .directory else { throw LibraryError.unsafePath }
    }

    private func relocationParent(in directory: URL, folders: [String], create: Bool) throws -> URL {
        try checkRelocationRoot(directory)
        var parent = directory
        for component in folders {
            guard safeRelocationComponent(component) else { throw LibraryError.unsafePath }
            parent.appendPathComponent(component, isDirectory: true)
            try Self.validateRoot(parent)
            switch try relocationNode(at: parent) {
            case .directory: break
            case .missing:
                if create {
                    do { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false) }
                    catch {
                        guard try relocationNode(at: parent) == .directory else { throw error }
                    }
                }
            default: throw LibraryError.unsafePath
            }
            guard parent.resolvingSymlinksInPath().path == parent.path else { throw LibraryError.unsafePath }
        }
        return parent
    }

    private enum RelocationNode { case missing, directory, file, other }

    private func relocationNode(at url: URL) throws -> RelocationNode {
        var info = stat()
        if lstat(url.path, &info) == 0 {
            switch info.st_mode & S_IFMT {
            case S_IFDIR: return .directory
            case S_IFREG: return .file
            default: return .other
            }
        }
        let code = errno
        if code == ENOENT { return .missing }
        throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
    }

    private func safeRelocationComponent(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 255 && name != "." && name != ".." && !name.contains("/") &&
            !name.contains(":") && name.rangeOfCharacter(from: .controlCharacters) == nil
    }

    private func relocationName(for photo: Photo, source: URL?) -> String {
        let name = photo.referencedPath == nil ? (photo.sourceName ?? photo.originalName)
            : (source?.lastPathComponent ?? photo.originalName)
        return safeRelocationComponent(name) ? name : photo.filename
    }

    private func relocationFilename(for photo: Photo, originalName: String, index: Int, preset: OriginalRelocationFilename) -> String {
        switch preset {
        case .original: return originalName
        case .catalogue:
            return safeRelocationComponent(photo.originalName) ? photo.originalName : photo.filename
        case .sequence:
            let ext = (photo.filename as NSString).pathExtension
            return String(format: "Original-%04d", index + 1) + (ext.isEmpty ? "" : "." + ext)
        }
    }

    private func relocationFolders(for photo: Photo, preset: OriginalRelocationSubfolders, projects: [UUID: String]) -> [String] {
        switch preset {
        case .none: return []
        case .project:
            guard let name = photo.projectID.flatMap({ projects[$0] }) else { return ["Unassigned"] }
            let unsafe = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
            let parts = name.components(separatedBy: unsafe).joined(separator: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            var folder = ""
            var length = 0
            for character in parts {
                let size = String(character).utf8.count
                guard length + size <= 180 else { break }
                folder.append(character)
                length += size
            }
            if folder.isEmpty { return ["Unassigned"] }
            if (try? Self.validateRoot(URL(fileURLWithPath: "/").appendingPathComponent(folder))) == nil {
                folder += " Project"
            }
            return [folder]
        case .captureMonth:
            let date = String(photo.captureDate.prefix(10))
            guard let day = PhotoQueryCriterion.dayNumber(date, separator: ":") else { return ["Unknown Capture Date"] }
            return [String(format: "%04d", day / 10000), String(format: "%02d", day / 100 % 100)]
        }
    }
}
