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
                if try repository.importPhoto(file, projectID: project?.id ?? projectID, into: &library, options: options, albumID: albumID) {
                    let id = library.photos[library.photos.count - 1].id
                    report.selection = id
                    if options.pairing.linksCompanions, ImportOptions.isRAW(file) || ImportOptions.isJPEG(file) {
                        pairs[ImportOptions.key(file), default: []].append((id, ImportOptions.isRAW(file)))
                    }
                    report.imported += 1
                } else {
                    report.duplicates += 1
                }
            } catch {
                report.errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
            }
            processed += 1
        }
        report.cancelled = Task.isCancelled && processed < files.count
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
                try repository.save(draft)
                library = draft
                report.selection = selection
            } catch {
                report.errors.append("RAW + JPEG linking: \(error.localizedDescription)")
            }
        }
        return report
    }
}
