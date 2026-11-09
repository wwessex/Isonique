import SwiftUI
import AppKit
import ImageIO
import IsoniqueCore
import UniformTypeIdentifiers

enum PhotoSort: String, CaseIterable, Identifiable {
    case imported = "Import date", name = "Filename", rating = "Rating", captured = "Capture date"
    var id: String { rawValue }
}
enum EditTool: String { case select, crop, straighten }
@MainActor final class Workspace: ObservableObject {
    @Published var library = Library()
    @Published var scope = "all"
    @Published var selection: UUID?
    @Published var batchMode = false
    @Published var batchSelection: Set<UUID> = []
    @Published var showAutoStack = false
    @Published var showSlideshow = false
    @Published var slideshowPhotos: [Photo] = []
    @Published var showSmartAlbum = false
    @Published var showAdvancedSearch = false
    @Published var advancedSearch: PhotoQuery?
    @Published var editingSmartAlbum: UUID?
    @Published var search = ""
    @Published var sort = PhotoSort.imported
    @Published var sortDescending = false
    @Published var stampGroups = Set(AdjustmentGroup.allCases)
    @Published var ratingFilter = RatingFilter.all
    @Published var originalFilter = OriginalFilter.all
    @Published var originalStatusRevision = 0
    @Published var busy = false
    @Published private(set) var importInProgress = false
    @Published private(set) var importProgress: ImportProgress?
    @Published private(set) var cancellingImport = false
    private var importTask: Task<(Library, ImportReport), Never>?
    @Published var status = "Ready · originals are preserved"
    @Published var error: String?
    @Published var viewer = false
    @Published var showInspector = true
    @Published var compareOriginal = false
    @Published var tool = EditTool.select
    @Published var liftedAdjustments: LiftedSettings?
    @Published var stampMetadata = Set<StampMetadata>()
    @Published var showExportOptions = false
    @Published var showImportOptions = false
    @Published var pendingImport: [URL] = []
    @Published var proofProfile: Data?
    @Published var proofName = ""
    @Published var proofEnabled = false
    @Published var history = EditHistory()
    var keepHistory: Bool { UserDefaults.standard.bool(forKey: "history.persist") }
    var canUndo: Bool { !history.undo.isEmpty }
    var canRedo: Bool { !history.redo.isEmpty }
    var repository: LibraryRepository?
    init(libraryRoot: URL? = nil) {
        do {
            let args = ProcessInfo.processInfo.arguments
            let root: URL
            if let libraryRoot {
                root = libraryRoot
            } else if let index = args.firstIndex(of: "--library"), args.indices.contains(index + 1) {
                root = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            } else if let saved = UserDefaults.standard.string(forKey: "library.selectedRoot") {
                root = URL(fileURLWithPath: saved, isDirectory: true)
                guard FileManager.default.fileExists(atPath: root.appendingPathComponent("catalog.json").path) else {
                    throw LibraryError.integrity("saved library is unavailable; use File → Open Isonique Library or Restore Library Backup")
                }
            } else {
                // Retain the existing storage path so rebranding never hides an existing catalogue.
                root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ApertureNative/Library", isDirectory: true)
            }
            let repo = try LibraryRepository(root: root)
            library = try repo.load()
            try repo.save(library)
            repository = repo
            history = keepHistory ? (library.history ?? EditHistory()) : EditHistory()
            selection = photos.first?.id
        } catch { self.error = error.localizedDescription; status = "Library unavailable" }
    }
    var isViewingTrash: Bool { scope == "trash" }
    var photos: [Photo] { filteredPhotos(advancedQuery: advancedSearch) }

    func filteredPhotos(advancedQuery: PhotoQuery?) -> [Photo] {
        let identifier = scope.split(separator: ":").last.flatMap { UUID(uuidString: String($0)) }
        let smartRule = scope.hasPrefix("album:") ? library.albums.first { $0.id == identifier }?.rule : nil
        return library.photos.filter { photo in
            guard (photo.trashedAt != nil) == isViewingTrash else { return false }
            let inScope: Bool
            if scope.hasPrefix("project:"), let identifier { inScope = photo.projectID == identifier }
            else if scope.hasPrefix("album:"), let identifier {
                inScope = smartRule?.includes(photo, originalAvailable: { self.isOriginalAvailable(photo) }) ?? photo.albumIDs.contains(identifier)
            }
            else if scope.hasPrefix("stack:"), let identifier { inScope = photo.stackID == identifier }
            else { inScope = true }
            return inScope &&
                originalFilter.includes(photo, repository: repository) &&
                BrowserFilterRules.includes(rating: photo.rating, flagged: photo.flagged, ratingFilter: ratingFilter, flaggedOnly: scope == "flagged") &&
                (search.isEmpty || [photo.originalName, photo.caption, photo.keywords, photo.camera].joined(separator: " ").localizedCaseInsensitiveContains(search)) &&
                (advancedQuery?.includes(photo, originalAvailable: { self.isOriginalAvailable(photo) }) ?? true)
        }.sorted { lhs, rhs in sortDescending ? orderedBefore(rhs, lhs) : orderedBefore(lhs, rhs) }
    }

    func isOriginalAvailable(_ photo: Photo) -> Bool? {
        guard let repository else { return nil }
        return (try? repository.availableOriginalURL(photo)) != nil
    }

    @discardableResult
    func saveSmartAlbum(name: String, rule: SmartAlbumRule, editingID: UUID? = nil) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, rule.query?.criteria.allSatisfy(\.isValid) != false else { return false }
        var draft = library
        var album = Collection(name: trimmed)
        album.rule = rule
        if let editingID, let index = draft.albums.firstIndex(where: { $0.id == editingID }) {
            album.id = editingID
            draft.albums[index] = album
        } else {
            draft.albums.append(album)
        }
        if rule.query != nil || rule.projectID != nil { draft.version = 2 }
        guard commit(draft) else { return false }
        showBrowser(allPhotos: true)
        scope = "album:\(album.id)"
        return true
    }
    private func orderedBefore(_ lhs: Photo, _ rhs: Photo) -> Bool {
        switch sort {
        case .imported: return lhs.importedAt == rhs.importedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.importedAt < rhs.importedAt
        case .name: return lhs.originalName == rhs.originalName ? lhs.id.uuidString < rhs.id.uuidString : lhs.originalName.localizedStandardCompare(rhs.originalName) == .orderedAscending
        case .rating: return lhs.rating == rhs.rating ? lhs.importedAt < rhs.importedAt : lhs.rating < rhs.rating
        case .captured: return lhs.captureDate == rhs.captureDate ? lhs.importedAt < rhs.importedAt : lhs.captureDate < rhs.captureDate
        }
    }
    var selected: Photo? { photos.first { $0.id == selection } }
    var title: String {
        if isViewingTrash { return "Trash" }
        if scope == "flagged" { return "Flagged" }
        if let project = library.projects.first(where: { scope == "project:\($0.id)" }) { return project.name }
        if let album = library.albums.first(where: { scope == "album:\($0.id)" }) { return album.name }
        if scope.hasPrefix("stack:") { return "Photo Stack" }
        return "All Photos"
    }
    @discardableResult
    func commit(_ draft: Library, history newHistory: EditHistory? = nil) -> Bool {
        guard !busy, let repository else { return false }
        let nextHistory = newHistory ?? history
        var saved = draft
        saved.history = keepHistory ? nextHistory : nil
        do {
            try repository.save(saved)
            library = saved
            if newHistory != nil { history = nextHistory }
            return true
        } catch {
            self.error = error.localizedDescription
            return false
        }
    }
    func save() { commit(library) }
    func undoEdit() { stepHistory(redo: false) }
    func redoEdit() { stepHistory(redo: true) }
    private func stepHistory(redo: Bool) {
        var nextHistory = history
        let photo = redo ? nextHistory.redo.popLast() : nextHistory.undo.popLast()
        guard let photo, let index = library.photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let current = library.photos[index]
        if redo { nextHistory.undo.append(current) } else { nextHistory.redo.append(current) }
        var draft = library
        draft.photos[index] = photo
        draft.photos[index].referencedPath = current.referencedPath
        guard commit(draft, history: nextHistory) else { return }
        selectAfterChange(preferred: photo.id)
    }
    func selectAfterChange(preferred: UUID?) {
        let visible = photos
        selection = visible.first { $0.id == preferred }?.id ?? visible.first?.id
        compareOriginal = false; tool = .select
        if visible.isEmpty { viewer = false }
    }
    var selectedTrashActionIDs: Set<UUID> {
        if batchMode { return Set(photos.map(\.id)).intersection(batchSelection) }
        return selected.map { [$0.id] } ?? []
    }
    func setPhotosTrashed(_ ids: Set<UUID>, trashed: Bool) {
        var draft = library
        let previous = draft.setPhotosTrashed(ids, at: trashed ? Date() : nil)
        guard commitPhotoChanges(draft, previous: previous) else { return }
        batchSelection.subtract(ids)
        selectAfterChange(preferred: selection)
        let description = previous.count == 1 ? "1 photo" : "\(previous.count) photos"
        status = trashed ? "Moved \(description) to Trash" : "Put back \(description)"
    }
    @discardableResult
    func commitPhotoChanges(_ draft: Library, previous: [Photo]) -> Bool {
        guard !previous.isEmpty else { return false }
        var nextHistory = history
        for photo in previous { nextHistory.record(photo) }
        return commit(draft, history: nextHistory)
    }
    func importMetadataPanel() {
        guard !busy, !isViewingTrash else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.xml, UTType(filenameExtension: "xmp") ?? .xml]
        panel.message = "Import XMP into the selected photo, or match XML records by unique source filename. Supported XML: Isonique photo records and AlbumData.xml metadata."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let records = try MetadataXML.read(url)
            var changes: [(Int, Photo)] = []
            for record in records {
                let matches = library.photos.indices.filter { index in
                    let photo = library.photos[index]
                    guard photo.trashedAt == nil else { return false }
                    if let name = record.filename { return (photo.sourceName ?? photo.originalName) == name }
                    return photo.id == selection
                }
                guard matches.count == 1 else { throw CocoaError(.fileReadCorruptFile) }
                changes.append((matches[0], record.applying(to: library.photos[matches[0]])))
            }
            var draft = library
            var previous: [Photo] = []
            for (index, photo) in changes where draft.photos[index] != photo {
                previous.append(draft.photos[index]); draft.photos[index] = photo
            }
            if previous.isEmpty || commitPhotoChanges(draft, previous: previous) {
                status = "Imported metadata for \(changes.count) records"
            }
        } catch { self.error = "Metadata import stopped: unsupported, malformed or ambiguous records. " + error.localizedDescription }
    }
    func chooseProofProfile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "icc") ?? .data, UTType(filenameExtension: "icm") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            guard let space = CGColorSpace(iccData: data as CFData), space.model == .rgb else { throw CocoaError(.fileReadCorruptFile) }
            proofProfile = data; proofName = url.lastPathComponent; proofEnabled = true
        } catch { self.error = "Choose a valid RGB ICC profile. CMYK printer proofing is not supported." }
    }
    func edit(_ change: (inout Photo) -> Void) {
        guard !busy, !isViewingTrash, let photo = selected else { return }
        var draft = library
        let previous = draft.updatePhotos([photo.id], change: change)
        commitPhotoChanges(draft, previous: previous)
    }
    // Original delta action 0x100032854 and rejection control 0x1004320d4.
    // Menu and inspector actions share the recovered rules and edit history.
    func adjustRating(by delta: Int) {
        edit { $0.rating = RatingRules.adjusting($0.rating, by: delta) }
    }
    func setRejected(_ rejected: Bool) {
        edit { $0.rating = RatingRules.rejectionRating(isRejected: rejected) }
    }
    func rotate(_ turns: Int) {
        compareOriginal = false; tool = .select
        edit { $0.adjustments.quarterTurns = (($0.adjustments.quarterTurns % 4) + turns + 4) % 4; $0.adjustments.crop = nil }
    }
    func flip(_ axis: FlipAxis) {
        compareOriginal = false; tool = .select
        edit { $0.adjustments.toggleFlip(axis) }
    }
    func showBrowser(allPhotos: Bool = false) {
        viewer = false; tool = .select; compareOriginal = false
        if allPhotos {
            scope = "all"; search = ""; ratingFilter = .all; originalFilter = .all; advancedSearch = nil
        }
    }
    func chooseTool(_ next: EditTool) {
        viewer = true; compareOriginal = false; tool = next
    }
    func nudgeStraighten(_ delta: Double) {
        edit {
            let angle = StraightenRules.applying(rotation: delta, to: $0.adjustments.straighten)
            guard angle != $0.adjustments.straighten else { return }
            $0.adjustments.straighten = angle
            $0.adjustments.crop = nil
        }
    }
    func lift() {
        // Original lift returns before resetting its clipboard if there is no version.
        guard !isViewingTrash, let selected else { return }
        liftedAdjustments = LiftedSettings(selected)
        status = "Settings lifted · select another photo and Stamp"
    }
    var batchPhotos: [Photo] { library.photos.filter { $0.trashedAt == nil && batchSelection.contains($0.id) } }
    func editBatch(_ change: (inout Photo) -> Void) {
        guard !busy, !isViewingTrash else { return }
        var draft = library
        let previous = draft.updatePhotos(Set(batchPhotos.map(\.id)), change: change)
        if commitPhotoChanges(draft, previous: previous) {
            status = "Updated \(previous.count) photos · Undo restores one photo at a time"
        }
    }
    func stackSelection() {
        guard StackRules.canStack(photoCount: batchPhotos.count) else { return }
        let id = UUID(); editBatch { $0.stackID = id }
    }
    func stamp() {
        guard !isViewingTrash, let liftedAdjustments, !stampGroups.isEmpty || !stampMetadata.isEmpty else { return }
        compareOriginal = false; tool = .select
        if batchMode { editBatch { $0 = liftedAdjustments.applying(to: $0, groups: stampGroups, metadata: stampMetadata) } }
        else { edit { $0 = liftedAdjustments.applying(to: $0, groups: stampGroups, metadata: stampMetadata) } }
        status = "Selected settings stamped · original preserved"
    }
    func binding<T>(_ path: WritableKeyPath<Photo, T>, fallback: T) -> Binding<T> {
        Binding(get: { self.selected?[keyPath: path] ?? fallback }, set: { value in self.edit { $0[keyPath: path] = value } })
    }
    func addCollection(_ name: String, project: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = Collection(name: trimmed)
        var draft = library
        if project { draft.projects.append(item) } else { draft.albums.append(item) }
        guard commit(draft) else { return }
        scope = project ? "project:\(item.id)" : "album:\(item.id)"
        selection = nil
    }
    func startSlideshow() {
        // Aperture _runSlideshowPromptForSettings: 0x1000495f1 checks isImportInProgress.
        guard !importInProgress else { error = "Wait for the import to finish before starting a slideshow."; return }
        guard !busy, !isViewingTrash, repository != nil else { return }
        slideshowPhotos = batchMode ? photos.filter { batchSelection.contains($0.id) } : photos
        showSlideshow = !slideshowPhotos.isEmpty
    }
    func importPanel() {
        guard !busy, repository != nil else { return }
        let panel = NSOpenPanel(); panel.title = "Import photographs"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        pendingImport = panel.urls; showImportOptions = true
    }
    func importURLs(_ urls: [URL], options: ImportOptions = ImportOptions(), newProjectName: String? = nil) {
        guard !busy, let repository else { return }
        busy = true; importInProgress = true; status = "Importing originals…"
        let initialLibrary = library
        let projectID = library.projects.first(where: { scope == "project:\($0.id)" })?.id
        let albumID = library.albums.first(where: { $0.rule == nil && scope == "album:\($0.id)" })?.id
        let task = Task.detached(priority: .userInitiated) {
            var draft = initialLibrary
            let report = await ImportJob.run(urls: urls, options: options, repository: repository, projectID: projectID,
                                             albumID: albumID, newProjectName: newProjectName, into: &draft) { progress in
                await self.reportImportProgress(progress)
            }
            return (draft, report)
        }
        importTask = task
        Task {
            let (draft, report) = await task.value
            library = draft
            if let project = report.createdProject {
                showBrowser(allPhotos: true)
                scope = "project:\(project)"
            }
            selection = report.selection ?? selection
            importTask = nil; importProgress = nil; cancellingImport = false
            importInProgress = false; busy = false
            let prefix = report.cancelled ? "Import cancelled · " : ""
            status = prefix + "Imported \(report.imported) · duplicates \(report.duplicates) · failed \(report.errors.count)"
            if !report.errors.isEmpty { error = report.errors.prefix(8).joined(separator: "\n") }
        }
    }

    private func reportImportProgress(_ progress: ImportProgress) {
        if !cancellingImport { importProgress = progress }
    }

    func cancelImport() {
        guard let importTask, !cancellingImport else { return }
        cancellingImport = true
        importTask.cancel()
    }
    func recoverPanel() {
        guard let repository, !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Recover originals from an Aperture library"
        panel.message = "A verified temporary copy is made first. Embedded Masters/Originals and any captions, keywords and ratings embedded in those files are recovered; legacy albums, adjustments and referenced originals are not migrated. Allow enough free space for a complete copy."
        panel.canChooseFiles = true; panel.canChooseDirectories = true; panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        busy = true; status = "Copying and verifying legacy library…"
        var snapshot = library
        Task {
            let result = await Task.detached { () -> (Library, String, String?) in
                do {
                    let counts = try repository.recoverLegacy(source, into: &snapshot)
                    let details = counts.unsupported.isEmpty ? nil : "Unsupported originals (first 20):\n" + counts.unsupported.prefix(20).joined(separator: "\n")
                    return (snapshot, "Recovered \(counts.imported) · duplicates \(counts.duplicates) · unsupported \(counts.unsupported.count) · source integrity verified", details)
                } catch { return (snapshot, "Recovery stopped", error.localizedDescription) }
            }.value
            library = result.0; status = result.1; error = result.2; busy = false
        }
    }
    func exportPanel() { if !isViewingTrash, (batchMode ? !batchPhotos.isEmpty : selected != nil) && !busy { showExportOptions = true } }
    func exportWithOptions(_ options: ExportOptions) {
        guard !isViewingTrash else { return }
        if batchMode { exportBatch(options); return }
        guard let photo = selected, let repository, !busy else { return }
        let panel = NSSavePanel()
        let suffix = options.format == .original ? (photo.filename as NSString).pathExtension : options.format.suffix
        panel.allowedContentTypes = options.format == .original ? [UTType(filenameExtension: suffix) ?? .data] : [options.format.type]
        let base = (photo.originalName as NSString).deletingPathExtension + (options.format == .original ? "-original" : "-edited")
        panel.nameFieldStringValue = suffix.isEmpty ? base : base + "." + suffix
        panel.message = options.format == .original ? "Copies the unchanged original, including all embedded metadata. Edits and metadata choices do not apply." : "Exports with adjustments and your selected metadata. Existing files are never overwritten."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        busy = true; status = "Rendering full-resolution export…"
        Task {
            let result = await Task.detached { () -> String? in
                do { try Renderer.export(photo, repository: repository, to: url, options: options); return nil }
                catch { return error.localizedDescription }
            }.value
            busy = false; error = result; status = result == nil ? "Exported \(url.lastPathComponent)" : "Export failed"
        }
    }
}

@main struct IsoniqueApp: App {
    @StateObject private var workspace = Workspace()
    @Environment(\.openWindow) private var openWindow
    var body: some Scene {
        WindowGroup("Isonique") {
            ContentView().environmentObject(workspace)
                .frame(minWidth: 1050, minHeight: 650)
                .preferredColorScheme(.dark)
                .onAppear {
                    NSApplication.shared.setActivationPolicy(.regular)
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    WindowScreenshot.shared.startIfRequested()
                    // An optional launch probe records a real ordered, visible AppKit window.
                    if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "--launch-report"), ProcessInfo.processInfo.arguments.indices.contains(i + 1) {
                        let path = ProcessInfo.processInfo.arguments[i + 1]
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            let windows = NSApplication.shared.windows.filter { $0.isVisible && $0.frame.width >= 1000 }
                            let report = "architecture=\(ProcessInfo.processInfo.machineArchitecture)\nvisibleWindows=\(windows.count)\ntitle=\(windows.first?.title ?? "")\n"
                            try? report.write(toFile: path, atomically: true, encoding: .utf8)
                        }
                    }
                }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Advanced Search…") { workspace.showAdvancedSearch = true }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .disabled(workspace.busy || workspace.repository == nil)
                Button("Clear Advanced Search") { workspace.advancedSearch = nil }
                    .disabled(workspace.advancedSearch == nil || workspace.busy)
            }
            CommandMenu("Review") {
                Button("Auto Stack by Capture Time…") { workspace.showAutoStack = true }.disabled(workspace.busy || workspace.isViewingTrash || workspace.photos.isEmpty)
                Button("Start Slideshow…") {
                    workspace.startSlideshow()
                }.disabled(workspace.busy || workspace.isViewingTrash || workspace.photos.isEmpty || workspace.repository == nil)
            }
            CommandMenu("Photos") {
                ForEach(FlipAxis.allCases) { axis in
                    Button(axis.rawValue) { workspace.flip(axis) }
                        .disabled(workspace.busy || workspace.isViewingTrash || workspace.selected == nil)
                }
            }
            CommandMenu("Rating") {
                Button("Raise Rating") { workspace.adjustRating(by: 1) }
                    .disabled(workspace.busy || workspace.isViewingTrash || workspace.selected == nil || (workspace.selected?.rating ?? RatingRules.maximum) >= RatingRules.maximum)
                Button("Lower Rating") { workspace.adjustRating(by: -1) }
                    .disabled(workspace.busy || workspace.isViewingTrash || workspace.selected == nil || (workspace.selected?.rating ?? RatingRules.rejected) <= RatingRules.rejected)
                Divider()
                Button(workspace.selected?.rating == RatingRules.rejected ? "Unreject Photo" : "Reject Photo") {
                    workspace.setRejected(workspace.selected?.rating != RatingRules.rejected)
                }
                .disabled(workspace.busy || workspace.isViewingTrash || workspace.selected == nil)
            }
            CommandGroup(replacing: .help) {
                Button("Features & Limits…") { openWindow(id: "features") }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Photo Edit") { workspace.undoEdit() }.keyboardShortcut("z").disabled(!workspace.canUndo || workspace.busy)
                Button("Redo Photo Edit") { workspace.redoEdit() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!workspace.canRedo || workspace.busy)
            }
            CommandGroup(after: .newItem) {
                Button("New Smart Album…") { workspace.editingSmartAlbum = nil; workspace.showSmartAlbum = true }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                    .disabled(workspace.busy || workspace.repository == nil)
                Button("Import Photos…", action: workspace.importPanel).keyboardShortcut("i").disabled(workspace.busy || workspace.repository == nil)
                if workspace.importInProgress {
                    Button("Cancel Import", action: workspace.cancelImport).disabled(workspace.cancellingImport)
                }
                Button("Import XML / XMP Metadata…", action: workspace.importMetadataPanel)
                    .disabled(workspace.busy || workspace.isViewingTrash || workspace.library.activePhotos.isEmpty)
                Button("Import & History Options…") { workspace.pendingImport = []; workspace.showImportOptions = true }.disabled(workspace.busy)
                Divider()
                Button("New Isonique Library…", action: workspace.createLibraryPanel).keyboardShortcut("n", modifiers: [.command, .shift]).disabled(workspace.busy)
                Button("Open Isonique Library…", action: workspace.openLibraryPanel).disabled(workspace.busy)
                Button("Back Up Library…", action: workspace.backupLibraryPanel).disabled(workspace.busy || workspace.repository == nil)
                Button("Check Library Integrity", action: workspace.verifyLibrary).disabled(workspace.busy || workspace.repository == nil)
                Button("Relink Original…") {
                    if let photo = workspace.selected { workspace.relinkOriginalPanel(photo) }
                }.disabled(workspace.busy || workspace.isViewingTrash || !workspace.canRelinkSelectedOriginal)
                Button("Consolidate Original") {
                    if let photo = workspace.selected { workspace.consolidateOriginal(photo) }
                }.disabled(workspace.busy || workspace.isViewingTrash || workspace.selected?.referencedPath == nil)
                Button("Refresh Original Status", action: workspace.refreshOriginalStatus).disabled(workspace.busy || workspace.repository == nil)
                Button("Restore Library Backup…", action: workspace.restoreLibraryPanel).disabled(workspace.busy)
                Button("Recover Aperture Originals…", action: workspace.recoverPanel).disabled(workspace.busy || workspace.repository == nil)
                Button("Export Photos…", action: workspace.exportPanel).keyboardShortcut("e", modifiers: [.command, .shift])
                    .disabled(workspace.isViewingTrash || (workspace.batchMode ? workspace.batchPhotos.isEmpty : workspace.selected == nil) || workspace.busy)
                Divider()
                Button(workspace.isViewingTrash ? "Put Back Photos" : "Move Photos to Trash") {
                    workspace.setPhotosTrashed(workspace.selectedTrashActionIDs, trashed: !workspace.isViewingTrash)
                }.keyboardShortcut(.delete, modifiers: [.command]).disabled(workspace.busy || workspace.selectedTrashActionIDs.isEmpty)
            }
        }
        Window("Features & Limits", id: "features") {
            FeatureGuide().preferredColorScheme(.dark)
        }
        .defaultSize(width: 720, height: 700)
    }
}
extension ProcessInfo {
    var machineArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "other"
        #endif
    }
}
// System Liquid Glass on macOS 26+, with native vibrancy on older systems.
private struct WorkspaceGlass: ViewModifier {
    var radius: CGFloat = 16
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(.white.opacity(0.12)))
        }
    }
}
private extension View {
    func workspaceGlass(radius: CGFloat = 16) -> some View { modifier(WorkspaceGlass(radius: radius)) }
}

struct ContentView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.openWindow) private var openWindow
    @State private var collectionName = ""
    @State private var creatingProject = true
    @State private var showCollection = false
    private var workspaceView: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.aperture").font(.system(size: 29, weight: .light)).foregroundStyle(.white).frame(width: 46, height: 46).workspaceGlass(radius: 14)
                    VStack(alignment: .leading) { Text("Isonique").font(.system(size: 22, weight: .semibold, design: .rounded)); Text("PHOTO WORKSPACE").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundStyle(.secondary) }
                }.padding(20)
                List(selection: $model.scope) {
                    Section("Library") {
                        Label("All Photos", systemImage: "photo.on.rectangle.angled").tag("all").simultaneousGesture(TapGesture().onEnded { model.showBrowser(allPhotos: true) })
                        Label("Flagged", systemImage: "flag").tag("flagged")
                        Label("Trash", systemImage: "trash").tag("trash")
                    }
                    Section("Projects") {
                        ForEach(model.library.projects) { project in Label(project.name, systemImage: "folder").tag("project:\(project.id)") }
                    }
                    Section("Stacks") {
                        ForEach(Array(Set(model.library.activePhotos.compactMap(\.stackID))).sorted { $0.uuidString < $1.uuidString }, id: \.self) { id in
                            Label(model.library.activePhotos.first(where: { $0.stackID == id })?.originalName ?? "Stack", systemImage: "square.3.layers.3d").tag("stack:\(id)")
                        }
                    }
                    Section("Albums") {
                        ForEach(model.library.albums) { album in Label(album.name, systemImage: album.rule == nil ? "rectangle.stack" : "gearshape.2").tag("album:\(album.id)")
                            .contextMenu {
                                if album.rule != nil { Button("Edit Smart Album…") { model.editingSmartAlbum = album.id; model.showSmartAlbum = true } }
                            } }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                HStack {
                    Menu { Button("New Project") { creatingProject = true; showCollection = true }; Button("New Album") { creatingProject = false; showCollection = true }; Button("New Smart Album…") { model.editingSmartAlbum = nil; model.showSmartAlbum = true } } label: { Image(systemName: "plus"); Text("Create") }
                        .menuStyle(.borderlessButton)
                    Spacer()
                    Text("\(model.library.activePhotos.count) photos").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.background(.ultraThinMaterial).navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    if model.viewer {
                        Button { model.showBrowser() } label: { Label("Back to \(model.title)", systemImage: "chevron.left") }
                            .help("Return to the photo grid; Escape also goes back")
                        if model.scope != "all" || !model.search.isEmpty || model.ratingFilter != .all || model.originalFilter != .all || model.advancedSearch != nil {
                            Button("All Photos") { model.showBrowser(allPhotos: true) }
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) { Text(model.title).font(.title2.weight(.semibold)); Text("\(model.photos.count) photographs").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if model.advancedSearch != nil {
                        Button("Clear Advanced Search", systemImage: "xmark.circle") { model.advancedSearch = nil }
                            .labelStyle(.iconOnly).help("Clear Advanced Search")
                    }
                    if model.isViewingTrash {
                        Button("Put Back") { model.setPhotosTrashed(model.selectedTrashActionIDs, trashed: false) }
                            .disabled(model.selectedTrashActionIDs.isEmpty)
                    }
                    Picker("Rating filter", selection: $model.ratingFilter) { ForEach(RatingFilter.allCases) { filter in Text(filter.label).tag(filter) } }.labelsHidden().frame(width: 165)
                    Picker("View", selection: $model.viewer) { Image(systemName: "square.grid.2x2").tag(false); Image(systemName: "rectangle.bottomthird.inset.filled").tag(true) }.labelsHidden().pickerStyle(.segmented).frame(width: 80)
                }.padding(.horizontal, 22).padding(.vertical, 16)
                Divider().opacity(0.4)
                if model.batchMode { BatchBar() }
                if !model.isViewingTrash { EditBar().disabled(model.batchMode) }
                Divider().opacity(0.4)
                HSplitView {
                    VStack(spacing: 0) {
                        if model.photos.isEmpty {
                            VStack(spacing: 18) {
                                Image(systemName: "camera.aperture").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(.secondary)
                                if model.isViewingTrash {
                                    Text("No matching photos in Trash").font(.title2)
                                    Text("Photos moved to Trash can be put back from here.").foregroundStyle(.secondary)
                                } else {
                                    Text(model.library.activePhotos.isEmpty ? "A new home for your photographs" : "No photographs in this view").font(.title2)
                                    Text("Import into projects. Organise with albums. Keep every original.").foregroundStyle(.secondary)
                                    Button(action: model.importPanel) { Label("Import Photographs…", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if model.viewer, let photo = model.selected, let repo = model.repository {
                            Group {
                                if let url = try? repo.availableOriginalURL(photo) {
                                    PhotoViewer(photo: photo, url: url, original: model.compareOriginal)
                                } else {
                                    MissingOriginalView(photo: photo)
                                }
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                            ScrollView(.horizontal) { LazyHStack(spacing: 10) { ForEach(model.photos) { photo in photoCell(photo, compact: true) } }.padding(12) }
                                .scrollIndicators(.hidden).frame(height: 128).workspaceGlass(radius: 18).padding(.horizontal, 16).padding(.bottom, 14)
                        } else {
                            ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 18) { ForEach(model.photos) { photo in photoCell(photo, compact: false) } }.padding(20) }
                        }
                    }.frame(minWidth: 400).background(Color(white: 0.055))
                    if model.showInspector && !model.isViewingTrash {
                        Inspector().frame(minWidth: 260, idealWidth: 290, maxWidth: 340).workspaceGlass(radius: 20).padding(10)
                    }
                }
                Divider()
                HStack(spacing: 8) {
                    if model.busy { ProgressView().controlSize(.small) } else { Image(systemName: "checkmark.shield").foregroundStyle(.secondary) }
                    Text(model.status).font(.caption).lineLimit(2)
                    Spacer()
                    Text("\(model.photos.count) photos").font(.caption2).foregroundStyle(.secondary)
                }.padding(.horizontal, 18).padding(.vertical, 10).background(.ultraThinMaterial)
            }
        }
        .disabled(model.busy || model.repository == nil)
        .searchable(text: $model.search, prompt: "Search names, keywords, cameras")
        .toolbar {
            ToolbarItem { Toggle("Select Photos", isOn: $model.batchMode).onChange(of: model.batchMode) { _, active in
                model.batchSelection = []; if active { model.showBrowser() }
            } }
            ToolbarItem { Button { openWindow(id: "features") } label: { Label("Features & Limits", systemImage: "questionmark.circle") }.help("See available features and what is still missing") }
            ToolbarItem { Button { withAnimation(.easeInOut(duration: 0.2)) { model.showInspector.toggle() } } label: { Label("Inspector", systemImage: "sidebar.right") }.help("Show or hide inspector") }
            ToolbarItem {
                Menu {
                    Picker("Sort by", selection: $model.sort) { ForEach(PhotoSort.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Descending", isOn: $model.sortDescending)
                    Divider()
                    Button("Advanced Search…") { model.showAdvancedSearch = true }
                    Divider()
                    Picker("Originals", selection: $model.originalFilter) {
                        ForEach(OriginalFilter.allCases) { filter in Text(filter.rawValue).tag(filter) }
                    }
                } label: { Label("Sort & Filter", systemImage: "arrow.up.arrow.down") }
            }
            ToolbarItem {
                Menu {
                    Button("Auto Stack by Capture Time…") { model.showAutoStack = true }
                    Button("Start Slideshow…") {
                        model.startSlideshow()
                    }
                } label: { Label("Review", systemImage: "play.rectangle") }.disabled(model.busy || model.isViewingTrash || model.photos.isEmpty || model.repository == nil)
            }
            ToolbarItem { Button(action: model.importPanel) { Label("Import", systemImage: "square.and.arrow.down") } }
            ToolbarItem { Button(action: model.exportPanel) { Label("Export", systemImage: "square.and.arrow.up") }.disabled(model.isViewingTrash || (model.batchMode ? model.batchPhotos.isEmpty : model.selected == nil)) }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            workspaceView
            if model.importInProgress { ImportProgressBar() }
        }
        .sheet(isPresented: $model.showAutoStack) { AutoStackView().environmentObject(model) }
        .sheet(isPresented: $model.showSlideshow) {
            if let repository = model.repository, !model.slideshowPhotos.isEmpty { SlideshowView(photos: model.slideshowPhotos, repository: repository) }
        }
        .sheet(isPresented: $model.showSmartAlbum) { SmartAlbumView().environmentObject(model) }
        .sheet(isPresented: $model.showAdvancedSearch) { AdvancedSearchView().environmentObject(model) }
        .sheet(isPresented: $model.showImportOptions) { ImportOptionsView().environmentObject(model) }
        .sheet(isPresented: $model.showExportOptions) { ExportOptionsView().environmentObject(model) }
        .sheet(isPresented: $showCollection) {
            VStack(alignment: .leading, spacing: 20) {
                Text(creatingProject ? "New Project" : "New Album").font(.title2)
                TextField("Name", text: $collectionName).frame(width: 320).onSubmit(createCollection)
                HStack { Button("Cancel") { showCollection = false }; Spacer(); Button("Create", action: createCollection).buttonStyle(.borderedProminent).disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(28)
        }
        .alert("Isonique", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: model.scope) { _, _ in
            if model.isViewingTrash {
                model.search = ""; model.ratingFilter = .all; model.originalFilter = .all; model.advancedSearch = nil
            }
            if model.selected == nil { model.selection = model.photos.first?.id }
            model.batchSelection = []
            model.showBrowser()
        }
        .onExitCommand { model.showBrowser() }
        .onChange(of: model.viewer) { _, viewing in if !viewing { model.tool = .select; model.compareOriginal = false } }
        .onChange(of: model.search) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.ratingFilter) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.originalFilter) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.advancedSearch) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in model.refreshOriginalStatus() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in model.refreshOriginalStatus() }
        .onChange(of: model.selection) { _, _ in model.tool = .select; model.compareOriginal = false }
    }
    func createCollection() { model.addCollection(collectionName, project: creatingProject); collectionName = ""; showCollection = false }
    @ViewBuilder func photoCell(_ photo: Photo, compact: Bool) -> some View {
        if let repo = model.repository {
            let url = try? repo.availableOriginalURL(photo)
            Button {
                if model.batchMode {
                    if !model.batchSelection.insert(photo.id).inserted { model.batchSelection.remove(photo.id) }
                    model.selection = photo.id
                } else { model.selection = photo.id; model.viewer = true }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Group {
                        if let url { Thumbnail(url: url) }
                        else { Label("Original unavailable", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.secondary) }
                    }.frame(height: compact ? 76 : 140).frame(maxWidth: .infinity).background(Color.black.opacity(0.3)).clipped()
                    HStack {
                        if model.batchMode { Image(systemName: model.batchSelection.contains(photo.id) ? "checkmark.circle.fill" : "circle") }
                        Text(photo.originalName).lineLimit(1)
                        if photo.stackID != nil { Image(systemName: "square.3.layers.3d") }
                        if photo.referencedPath != nil { Image(systemName: "link").accessibilityLabel("Referenced original") }
                    }.font(.caption)
                    if !compact { HStack { Text(photo.rating == RatingRules.rejected ? "Rejected" : RatingRules.stars(photo.rating)).foregroundStyle(.orange); Spacer(); if photo.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange) } }.font(.caption).frame(height: 14) }
                }.padding(7).frame(width: compact ? 110 : nil)
                    .background((model.batchMode ? model.batchSelection.contains(photo.id) : model.selection == photo.id) ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke((model.batchMode ? model.batchSelection.contains(photo.id) : model.selection == photo.id) ? Color.accentColor : Color.white.opacity(0.07), lineWidth: (model.batchMode ? model.batchSelection.contains(photo.id) : model.selection == photo.id) ? 2 : 1))
            }.buttonStyle(.plain)
            .contextMenu {
                Button(model.isViewingTrash ? "Put Back" : "Move to Trash") {
                    model.setPhotosTrashed([photo.id], trashed: !model.isViewingTrash)
                }
                if !model.isViewingTrash {
                    if let url { Button("Reveal Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                    if photo.referencedPath != nil || url == nil {
                        Button("Relink Original…") { model.relinkOriginalPanel(photo) }
                    }
                    if photo.referencedPath != nil, url != nil {
                        Button("Consolidate Original") { model.consolidateOriginal(photo) }
                    }
                }
            }
        }
    }
}
struct EditBar: View {
    @EnvironmentObject var model: Workspace
    var body: some View {
        VStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                controls
                ScrollView(.horizontal) { controls }.scrollIndicators(.hidden)
            }
            if model.tool == .straighten {
                HStack {
                    Text("Straighten").font(.caption)
                    Button { model.nudgeStraighten(-0.1) } label: { Image(systemName: "minus") }
                        .help("Decrease straighten angle by 0.1°").accessibilityLabel("Decrease straighten angle by 0.1 degrees")
                    Slider(value: Binding(get: { model.selected?.adjustments.straighten ?? 0 }, set: { value in
                        model.edit { $0.adjustments.straighten = StraightenRules.clamp(value); $0.adjustments.crop = nil }
                    }), in: StraightenRules.range).frame(maxWidth: 280).accessibilityLabel("Straighten angle")
                    Button { model.nudgeStraighten(0.1) } label: { Image(systemName: "plus") }
                        .help("Increase straighten angle by 0.1°").accessibilityLabel("Increase straighten angle by 0.1 degrees")
                    Text("\(model.selected?.adjustments.straighten ?? 0, specifier: "%.1f")°").monospacedDigit().font(.caption).frame(width: 48)
                    Button("Level") { model.edit { $0.adjustments.straighten = 0; $0.adjustments.crop = nil } }
                    Button("Done") { model.tool = .select }
                    Spacer()
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial)
    }
    var controls: some View {
        HStack(spacing: 14) {
            Group {
                tool("Select", icon: "cursorarrow", mode: .select)
                Button { model.rotate(-1) } label: { Label("Left", systemImage: "rotate.left") }.help("Rotate 90° left; clears crop")
                Button { model.rotate(1) } label: { Label("Right", systemImage: "rotate.right") }.help("Rotate 90° right; clears crop")
                Menu {
                    ForEach(FlipAxis.allCases) { axis in Button(axis.rawValue) { model.flip(axis) } }
                } label: { Label("Flip", systemImage: "arrow.left.and.right") }
                Divider().frame(height: 20)
                tool("Crop", icon: "crop", mode: .crop)
                tool("Straighten", icon: "level", mode: .straighten)
                Divider().frame(height: 20)
                Button(action: model.lift) { Label("Lift", systemImage: "eyedropper") }.help("Copy adjustments from this photo")
                Button(action: model.stamp) { Label("Stamp", systemImage: "eyedropper.full") }.disabled(model.liftedAdjustments == nil || (model.stampGroups.isEmpty && model.stampMetadata.isEmpty)).help("Apply the adjustments and metadata selected in Inspector")
                Divider().frame(height: 20)
                Toggle(isOn: $model.compareOriginal) { Label("Original", systemImage: "square.on.square") }.toggleStyle(.button).disabled(model.tool != .select).help("Compare with the untouched original")
            }.disabled(model.selected == nil)
            Button { model.undoEdit() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.canUndo).help("Undo photo edit").accessibilityLabel("Undo photo edit")
            Button { model.redoEdit() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.canRedo).help("Redo photo edit").accessibilityLabel("Redo photo edit")
        }.buttonStyle(.borderless).font(.caption).fixedSize(horizontal: true, vertical: false)
    }
    func tool(_ title: String, icon: String, mode: EditTool) -> some View {
        Button { model.chooseTool(mode) } label: { Label(title, systemImage: icon).foregroundStyle(model.tool == mode ? Color.accentColor : .primary) }.help(title)
    }
}
struct Thumbnail: View {
    let url: URL
    @State private var image: NSImage?
    var body: some View {
        Group { if let image { Image(nsImage: image).resizable().scaledToFit() } else { Image(systemName: "photo").foregroundStyle(.secondary) } }
            .task(id: url) {
                let cg = await Task.detached(priority: .utility) { () -> CGImage? in
                    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
                    return CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 360, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary)
                }.value
                if !Task.isCancelled, let cg { image = NSImage(cgImage: cg, size: .zero) }
            }
    }
}
struct PhotoViewer: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    let url: URL
    let original: Bool
    @State private var image: NSImage?
    @State private var failure: String?
    @State private var zoom = false
    @State private var cropSize = CGSize(width: 1, height: 1)
    @AppStorage("crop.aspect") private var cropAspect = 0.0
    @AppStorage("crop.locked") private var cropLocked = false
    @State private var draft = PhotoCrop(x: 0, y: 0, width: 1, height: 1)
    var body: some View {
        VStack(spacing: 10) {
            
            if let image {
                if model.tool == .crop { CropCanvas(image: image, crop: $draft, pixelSize: cropSize, aspect: cropLocked && cropAspect > 0 ? cropAspect : nil).padding(16) }
                else if zoom && model.tool == .select { ScrollView([.horizontal, .vertical]) { Image(nsImage: image) } }
                else {
                    Image(nsImage: image).resizable().scaledToFit()
                        .overlay {
                            if model.tool == .straighten {
                                GeometryReader { geometry in
                                    Path { path in
                                        for n in 1...8 {
                                            let x = geometry.size.width * CGFloat(n) / 9, y = geometry.size.height * CGFloat(n) / 9
                                            path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                                            path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                                        }
                                    }.stroke(.yellow.opacity(0.5), lineWidth: 0.5)
                                }.allowsHitTesting(false)
                            }
                        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else if let failure { ContentUnavailableView("Image unavailable", systemImage: "exclamationmark.triangle", description: Text(failure)) }
            else { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.overlay(alignment: .top) {
            HStack(spacing: 14) {
                Image(systemName: original ? "photo" : "slider.horizontal.3").foregroundStyle(.secondary)
                Text(photo.originalName).font(.caption.weight(.medium)).lineLimit(1)
                if original { Text("Original").font(.caption).foregroundStyle(.secondary) }
                if model.proofEnabled { Text("RGB Proof").font(.caption).foregroundStyle(.yellow) }
                Divider().frame(height: 16)
                Button(zoom ? "Fit" : "100%") { zoom.toggle() }.buttonStyle(.plain).font(.caption.monospacedDigit()).help("Toggle actual pixels").disabled(model.tool != .select)
            }.padding(.horizontal, 16).padding(.vertical, 11).workspaceGlass(radius: 24).padding(16)
        }.safeAreaInset(edge: .bottom) {
            if model.tool == .crop {
                CropOptionsView(crop: $draft, aspect: $cropAspect, locked: $cropLocked, size: cropSize,
                    cancel: { model.tool = .select }, apply: { model.edit { $0.adjustments.crop = draft }; model.tool = .select })
                    .padding(12).workspaceGlass().padding(8)
            }
        }.padding(.top, 8)
        .onChange(of: model.tool) { _, tool in if tool == .crop { draft = photo.adjustments.crop ?? PhotoCrop(x: 0, y: 0, width: 1, height: 1) } }
        .task(id: "\(photo.id)-\(url.path)-\(model.originalStatusRevision)-\(photo.adjustments)-\(original)-\(zoom)-\(model.tool)-\(model.proofEnabled)-\(model.proofProfile?.hashValue ?? 0)") {
            var settings = original ? Adjustments() : photo.adjustments
            if model.tool == .crop { settings.crop = nil }
            if model.tool == .crop, let size = try? Renderer.dimensions(url, adjustments: settings) { cropSize = size }
            let maximum: CGFloat? = zoom && model.tool == .select ? nil : 2400
            let profile = model.proofEnabled ? model.proofProfile : nil
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CGImage, Error> in
                Result {
                    let rendered = try Renderer.render(url, adjustments: settings, maxDimension: maximum)
                    return try profile.map { try Renderer.proof(rendered, profile: $0) } ?? rendered
                }
            }.value
            guard !Task.isCancelled else { return }
            switch result { case .success(let cg): image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)); failure = nil
            case .failure(let error): image = nil; failure = error.localizedDescription }
        }
    }
}
struct Inspector: View {
    @EnvironmentObject var model: Workspace
    @State private var tab = "Adjustments"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Label("Inspector", systemImage: "slider.horizontal.3").font(.headline)
                if model.batchMode { Text("This inspector edits one photo. Use the selection bar above for batch actions.").font(.caption).foregroundStyle(.secondary) }
                if let photo = model.selected {
                    Text(photo.originalName).font(.headline).textSelection(.enabled)
                    Picker("Inspector section", selection: $tab) {
                        Text("Info").tag("Info")
                        Text("Adjustments").tag("Adjustments")
                        Text("Library").tag("Library")
                    }.pickerStyle(.segmented).labelsHidden()
                    if tab == "Info" { info(photo) }
                    if tab == "Adjustments" { adjustments(photo); VersionsView(photo: photo) }
                    if tab == "Library" { organisation() }
                } else {
                    Text("Select a photograph to view metadata and adjustments.").foregroundStyle(.secondary)
                    Divider()
                    Text("Isonique preserves your originals. Camera RAW support depends on macOS decoders; editing uses Isonique’s own pixel formulas.").font(.caption).foregroundStyle(.secondary)
                    Button("Import XML / XMP Metadata…", action: model.importMetadataPanel).disabled(model.busy || model.library.activePhotos.isEmpty)
                Button("Import & History Options…") { model.pendingImport = []; model.showImportOptions = true }
                Button("Recover Aperture Originals…", action: model.recoverPanel)
                    Text("Recovery copies and verifies the source first. Legacy albums, referenced files and editing recipes are not migrated.").font(.caption).foregroundStyle(.secondary)
                }
            }.padding(18)
        }.scrollIndicators(.hidden)
    }
    func info(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(photo.width) × \(photo.height) · \((photo.originalName as NSString).pathExtension.uppercased())").font(.caption).foregroundStyle(.secondary)
            if !photo.camera.isEmpty { LabeledContent("Camera", value: photo.camera) }
            if !photo.captureDate.isEmpty { LabeledContent("Captured", value: photo.captureDate) }
            LabeledContent("Imported", value: photo.importedAt.formatted(date: .abbreviated, time: .shortened))
            HStack(spacing: 6) {
                ForEach(1...RatingRules.maximum, id: \.self) { rating in Button { model.edit { $0.rating = rating } } label: { Image(systemName: photo.rating >= rating ? "star.fill" : "star").foregroundStyle(.orange) }.buttonStyle(.plain).help("Rate \(rating) stars") }
                Spacer()
                Toggle(isOn: model.binding(\.flagged, fallback: false)) { Image(systemName: "flag.fill") }.toggleStyle(.button).help("Flag photograph")
            }
            HStack {
                Toggle("Rejected", isOn: Binding(get: { photo.rating == RatingRules.rejected }, set: { model.setRejected($0) }))
                Button("Unrated") { model.edit { $0.rating = RatingRules.unrated } }
            }
            HStack {
                Button("Lower Rating") { model.adjustRating(by: -1) }
                    .disabled(photo.rating <= RatingRules.rejected)
                Button("Raise Rating") { model.adjustRating(by: 1) }
                    .disabled(photo.rating >= RatingRules.maximum)
            }
            if let pair = photo.pairID {
                Text("Linked RAW + JPEG").foregroundStyle(.secondary)
                ForEach(model.library.activePhotos.filter { $0.pairID == pair && $0.id != photo.id }) { companion in
                    Button("View " + companion.originalName) { model.selection = companion.id }
                }
            }
            Text("Caption").font(.caption).foregroundStyle(.secondary)
            TextField("Caption", text: model.binding(\.caption, fallback: ""), axis: .vertical)
            Text("Keywords").font(.caption).foregroundStyle(.secondary)
            TextField("Keywords, separated by commas", text: model.binding(\.keywords, fallback: ""))
            OriginalInfoView(photo: photo)
        }.font(.caption)
    }
    func adjustments(_ photo: Photo) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Menu {
                ForEach(AdjustmentPreset.allCases) { preset in
                    Button(preset.rawValue) {
                        model.compareOriginal = false
                        model.edit { $0.adjustments = preset.applying(to: $0.adjustments) }
                    }
                }
            } label: { Label("Apply Preset", systemImage: "slider.horizontal.3") }
            Text("Presets replace color and tone settings; crop and rotation are kept.").font(.caption2).foregroundStyle(.secondary)
            adjustment("Exposure", path: \.adjustments.exposure, range: -4...4)
            adjustment("Brightness", path: \.adjustments.brightness, range: -1...1)
            adjustment("Contrast", path: \.adjustments.contrast, range: 0.5...1.5, neutral: 1)
            adjustment("Saturation", path: \.adjustments.saturation, range: 0...2, neutral: 1)
            adjustment("Vibrancy", path: \.adjustments.vibrancy, range: -1...1)
            adjustment("Sepia", path: \.adjustments.sepia, range: 0...1)
            Divider()
            Text("WHITE BALANCE").font(.caption).foregroundStyle(.secondary)
            adjustment("Warmth", path: \.adjustments.warmth, range: -1...1)
            adjustment("Tint", path: \.adjustments.tint, range: -1...1)
            Divider()
            HistogramView(photo: photo)
            DisclosureGroup("Levels") {
                VStack(spacing: 10) {
                    adjustment("Black point", path: \.adjustments.blackPoint, range: 0...max(0, photo.adjustments.whitePoint - 0.01))
                    adjustment("White point", path: \.adjustments.whitePoint, range: min(1, photo.adjustments.blackPoint + 0.01)...1, neutral: 1)
                    adjustment("Gamma", path: \.adjustments.gamma, range: 0.1...4, neutral: 1)
                    Button("Reset Levels") { model.edit { $0.adjustments.blackPoint = 0; $0.adjustments.whitePoint = 1; $0.adjustments.gamma = 1 } }
                }.padding(.top, 10)
            }
            DisclosureGroup("Master Tone Curve") {
                VStack(spacing: 10) {
                    ToneCurveGraph(adjustments: photo.adjustments)
                    adjustment("Shadow output", path: \.adjustments.curveShadows, range: 0...1, neutral: 0.25)
                    adjustment("Midtone output", path: \.adjustments.curveMidtones, range: 0...1, neutral: 0.5)
                    adjustment("Highlight output", path: \.adjustments.curveHighlights, range: 0...1, neutral: 0.75)
                    Button("Reset Curve") { model.edit { $0.adjustments.curveShadows = 0.25; $0.adjustments.curveMidtones = 0.5; $0.adjustments.curveHighlights = 0.75 } }
                }.padding(.top, 10)
            }
            Text("HIGHLIGHTS & SHADOWS").font(.caption).foregroundStyle(.secondary)
            adjustment("Shadows", path: \.adjustments.shadows, range: 0...1)
            adjustment("Highlights", path: \.adjustments.highlights, range: -1...0)
            DisclosureGroup("Color Proofing & Lens") {
                VStack(alignment: .leading, spacing: 10) {
                    Button("Choose RGB ICC Profile…", action: model.chooseProofProfile)
                    Toggle("Proof preview", isOn: $model.proofEnabled).disabled(model.proofProfile == nil)
                    Text(model.proofName.isEmpty ? "Choose a profile to simulate RGB output color." : model.proofName).font(.caption2)
                    Text("Proofing affects the viewer only. RGB profiles only; no paper/ink simulation.").font(.caption2).foregroundStyle(.secondary)
                    adjustment("Lens distortion", path: \.adjustments.lensDistortion, range: -1...1)
                    Text("Manual barrel/pincushion correction applies to preview and export; no automatic lens profiles. Edge pixels are extended.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            DisclosureGroup("Crop & Rotation") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Button("Rotate Left") { model.rotate(-1) }; Button("Rotate Right") { model.rotate(1) } }
                    Toggle("Flip horizontally", isOn: Binding(get: { photo.adjustments.flipHorizontal }, set: { _ in model.flip(.horizontal) }))
                    Toggle("Flip vertically", isOn: Binding(get: { photo.adjustments.flipVertical }, set: { _ in model.flip(.vertical) }))
                    Button(photo.adjustments.crop == nil ? "Crop…" : "Edit Crop…") { model.chooseTool(.crop) }
                    Button("Remove Crop") { model.tool = .select; model.edit { $0.adjustments.crop = nil } }.disabled(photo.adjustments.crop == nil)
                    adjustment("Straighten", path: \.adjustments.straighten, range: StraightenRules.range, clearsCrop: true)
                    Text("Rotation and straightening clear an existing crop.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            DisclosureGroup("Lift & Stamp Options") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AdjustmentGroup.allCases) { group in
                        Toggle(group.rawValue, isOn: Binding(get: { model.stampGroups.contains(group) }, set: { included in
                            if included { model.stampGroups.insert(group) } else { model.stampGroups.remove(group) }
                        }))
                    }
                    Divider()
                    Text("Metadata (replaces selected fields)").font(.caption)
                    ForEach(StampMetadata.allCases) { field in
                        Toggle(field.rawValue, isOn: Binding(get: { model.stampMetadata.contains(field) }, set: { included in
                            if included { model.stampMetadata.insert(field) } else { model.stampMetadata.remove(field) }
                        }))
                    }
                    HStack { Button("Lift", action: model.lift); Button("Stamp", action: model.stamp).disabled(model.liftedAdjustments == nil || (model.stampGroups.isEmpty && model.stampMetadata.isEmpty)) }
                    Text("Lift captures adjustments, caption, keywords and rating. Stamp replaces only checked fields, including empty values. Metadata is unchecked by default.").font(.caption2).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            Toggle("Show original", isOn: $model.compareOriginal).disabled(model.tool != .select)
            Button("Reset All Adjustments") { model.tool = .select; model.compareOriginal = false; model.edit { $0.adjustments = Adjustments() } }
            Text("Edits are saved separately. Originals are never rewritten.").font(.caption2).foregroundStyle(.secondary)
            Button("Export Photo…", action: model.exportPanel)
        }
    }
    func organisation() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("PROJECT").font(.caption).foregroundStyle(.secondary)
            Picker("Project", selection: model.binding(\.projectID, fallback: nil)) { Text("Unassigned").tag(nil as UUID?); ForEach(model.library.projects) { Text($0.name).tag(Optional($0.id)) } }
            Text("ALBUMS").font(.caption).foregroundStyle(.secondary)
            if model.library.albums.isEmpty { Text("Create an album using Create in the sidebar.").font(.caption).foregroundStyle(.secondary) }
            ForEach(model.library.albums.filter { $0.rule == nil }) { album in
                Toggle(album.name, isOn: Binding(get: { model.selected?.albumIDs.contains(album.id) ?? false }, set: { included in model.edit { if included { $0.albumIDs.insert(album.id) } else { $0.albumIDs.remove(album.id) } } }))
            }
        }
    }
    func adjustment(_ title: String, path: WritableKeyPath<Photo, Double>, range: ClosedRange<Double>, neutral: Double = 0, clearsCrop: Bool = false) -> some View {
        let value = Binding<Double>(get: { model.selected?[keyPath: path] ?? neutral }, set: { input in
            guard input.isFinite else { return }
            model.compareOriginal = false
            model.edit { photo in
                photo[keyPath: path] = min(range.upperBound, max(range.lowerBound, input))
                if clearsCrop { photo.adjustments.crop = nil }
            }
        })
        return VStack(spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: value, format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).frame(width: 60).multilineTextAlignment(.trailing)
                Button { value.wrappedValue = neutral } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.borderless).help("Reset \(title)").accessibilityLabel("Reset \(title)")
            }.font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}
