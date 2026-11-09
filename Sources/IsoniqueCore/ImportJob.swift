import Foundation

public struct ImportProgress: Equatable, Sendable {
    public let processed: Int
    public let total: Int
    public let filename: String?
}

public struct ImportReport {
    public fileprivate(set) var imported = 0
    public fileprivate(set) var duplicates = 0
    public fileprivate(set) var errors: [String] = []
    public fileprivate(set) var selection: UUID?
    public fileprivate(set) var createdProject: UUID?
    public fileprivate(set) var cancelled = false

    public init() {}
    public init(sourceError error: Error) {
        if error is CancellationError { cancelled = true }
        else { errors = [error.localizedDescription] }
    }
}

public enum ImportJob {
    public static func run(urls: [URL], options: ImportOptions, repository: LibraryRepository,
                           projectID: UUID?, albumID: UUID?, newProjectName: String? = nil,
                           into library: inout Library,
                           progress: (ImportProgress) async -> Void = { _ in }) async -> ImportReport {
        var report = ImportReport()
        var candidates: [URL] = []
        for url in urls {
            if Task.isCancelled { break }
            if ["aplibrary", "aperturelibrary", "photoslibrary", "photolibrary", "app"].contains(url.pathExtension.lowercased()) {
                report.errors.append("\(url.lastPathComponent): use legacy recovery")
                continue
            }
            var directory: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
            candidates += directory.boolValue ? LibraryRepository.imageFiles(in: url, shouldContinue: { !Task.isCancelled }) : [url]
        }
        return await runFiles(candidates, options: options, repository: repository, projectID: projectID, albumID: albumID,
                              newProjectName: newProjectName, into: &library, report: report, progress: progress) { file in
            PreparedImport(file: file)
        }
    }

    public static func run(memoryCard card: MemoryCardSource, options: ImportOptions, repository: LibraryRepository,
                           projectID: UUID?, albumID: UUID?, newProjectName: String? = nil, into library: inout Library,
                           progress: (ImportProgress) async -> Void = { _ in }) async -> ImportReport {
        do { try card.checkAvailable() }
        catch { return ImportReport(sourceError: error) }
        let candidates = card.photoFiles()
        if candidates.isEmpty, !Task.isCancelled {
            do { try card.checkAvailable() }
            catch { return ImportReport(sourceError: error) }
            return ImportReport(sourceError: DeviceImportError.noPhotos)
        }
        var managed = options
        managed.storage = .managed
        return await runFiles(candidates, options: managed, repository: repository, projectID: projectID, albumID: albumID,
                              newProjectName: newProjectName, into: &library, progress: progress) { file in
            try card.validateFile(file)
            if options.readSidecars {
                let sidecar = file.deletingPathExtension().appendingPathExtension("xmp")
                if FileManager.default.fileExists(atPath: sidecar.path) { try card.validateFile(sidecar) }
            }
            return PreparedImport(file: file)
        }
    }

    public static func run(cameraFiles: [CameraImportFile], options: ImportOptions, repository: LibraryRepository,
                           projectID: UUID?, albumID: UUID?, newProjectName: String? = nil, into library: inout Library,
                           download: (CameraImportFile, URL) async throws -> Void,
                           progress: (ImportProgress) async -> Void = { _ in }) async -> ImportReport {
        if Task.isCancelled { return ImportReport(sourceError: CancellationError()) }
        let photos = Dictionary(grouping: cameraFiles.filter(\.isPhoto), by: \.logicalURL)
        let sidecars = Dictionary(grouping: cameraFiles.filter(\.isSidecar)) { ImportOptions.key($0.logicalURL) }
        guard !photos.isEmpty else { return ImportReport(sourceError: DeviceImportError.noPhotos) }
        var managed = options
        managed.storage = .managed
        return await runFiles(Array(photos.keys), options: managed, repository: repository, projectID: projectID, albumID: albumID,
                              newProjectName: newProjectName, into: &library, progress: progress) { url in
            guard let matches = photos[url], matches.count == 1, let item = matches.first else {
                throw DeviceImportError.ambiguous(url.lastPathComponent)
            }
            let fm = FileManager.default
            let staging = fm.temporaryDirectory.appendingPathComponent("IsoniqueCamera-\(UUID())", isDirectory: true)
            try fm.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            let file = staging.appendingPathComponent(item.filename)
            func stage(_ item: CameraImportFile, at destination: URL) async throws {
                try Task.checkCancellation()
                try await download(item, destination)
                try Task.checkCancellation()
                try LibraryBackup.regularFile(destination)
                if let size = item.byteCount,
                   try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init) != size {
                    throw DeviceImportError.incompleteDownload(item.filename)
                }
            }
            do {
                try await stage(item, at: file)
                if options.readSidecars, let matches = sidecars[ImportOptions.key(url)] {
                    guard matches.count == 1, let xmp = matches.first else {
                        throw DeviceImportError.ambiguous(url.deletingPathExtension().lastPathComponent + ".xmp")
                    }
                    try await stage(xmp, at: file.deletingPathExtension().appendingPathExtension("xmp"))
                }
                return PreparedImport(file: file, staging: staging)
            } catch {
                try? fm.removeItem(at: staging)
                throw error
            }
        }
    }

    private struct PreparedImport {
        let file: URL
        var staging: URL?
    }

    private static func runFiles(_ candidates: [URL], options: ImportOptions, repository: LibraryRepository,
                                 projectID: UUID?, albumID: UUID?, newProjectName: String?, into library: inout Library,
                                 report initial: ImportReport = ImportReport(), progress: (ImportProgress) async -> Void,
                                 prepare: (URL) async throws -> PreparedImport) async -> ImportReport {
        var report = initial
        if Task.isCancelled {
            report.cancelled = true
            return report
        }

        let files = options.files(candidates)
        let project = newProjectName.map(Collection.init(name:))
        if let project { library.projects.append(project) }
        var pairs: [String: [(id: UUID, raw: Bool)]] = [:]
        var processed = 0
        for file in files {
            if Task.isCancelled { break }
            await progress(ImportProgress(processed: processed, total: files.count, filename: file.lastPathComponent))
            if Task.isCancelled { break }
            do {
                let prepared = try await prepare(file)
                defer { if let staging = prepared.staging { try? FileManager.default.removeItem(at: staging) } }
                try Task.checkCancellation()
                if try repository.importPhoto(prepared.file, projectID: project?.id ?? projectID, into: &library, options: options, albumID: albumID) {
                    let id = library.photos[library.photos.count - 1].id
                    report.selection = id
                    if options.pairing.linksCompanions, ImportOptions.isRAW(file) || ImportOptions.isJPEG(file) {
                        pairs[ImportOptions.key(file), default: []].append((id, ImportOptions.isRAW(file)))
                    }
                    report.imported += 1
                } else {
                    report.duplicates += 1
                }
            } catch is CancellationError {
                report.cancelled = true
                break
            } catch {
                report.errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
                if (error as? DeviceImportError)?.stopsImport == true { break }
            }
            processed += 1
        }
        report.cancelled = report.cancelled || (Task.isCancelled && processed < files.count)
        if let project {
            if report.imported == 0 { library.projects.removeAll { $0.id == project.id } }
            else { report.createdProject = project.id }
        }
        if processed > 0 {
            await progress(ImportProgress(processed: processed, total: files.count, filename: nil))
        }

        // Finish links for the files that committed before cancellation.
        var assignments: [UUID: UUID] = [:]
        var selection = report.selection
        for members in pairs.values where members.contains(where: \.raw) && members.contains(where: { !$0.raw }) {
            let pairID = UUID()
            for member in members { assignments[member.id] = pairID }
            if members.contains(where: { $0.id == report.selection }) {
                selection = members.first { $0.raw == (options.pairing == .linkedRAW) }?.id
            }
        }
        if !assignments.isEmpty {
            var draft = library
            for index in draft.photos.indices {
                if let pairID = assignments[draft.photos[index].id] { draft.photos[index].pairID = pairID }
            }
            do {
                library = try repository.save(draft)
                report.selection = selection
            } catch {
                report.errors.append("RAW + JPEG linking: \(error.localizedDescription)")
            }
        }
        return report
    }
}
