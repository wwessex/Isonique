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
    @Published var search = ""
    @Published var sort = PhotoSort.imported
    @Published var sortDescending = false
    @Published var stampGroups = Set(AdjustmentGroup.allCases)
    @Published var ratingFilter = RatingFilter.all
    @Published var busy = false
    @Published var status = "Ready · originals are preserved"
    @Published var error: String?
    @Published var viewer = true
    @Published var showInspector = true
    @Published var compareOriginal = false
    @Published var tool = EditTool.select
    @Published var liftedAdjustments: LiftedSettings?
    @Published var stampMetadata = Set<StampMetadata>()
    @Published var showExportOptions = false
    let editUndo = UndoManager()
    var repository: LibraryRepository?
    init() {
        do {
            let args = ProcessInfo.processInfo.arguments
            let root: URL
            if let index = args.firstIndex(of: "--library"), args.indices.contains(index + 1) {
                root = URL(fileURLWithPath: args[index + 1], isDirectory: true)
            } else {
                // Retain the existing storage path so rebranding never hides an existing catalogue.
                root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ApertureNative/Library", isDirectory: true)
            }
            let repo = try LibraryRepository(root: root)
            library = try repo.load()
            try repo.save(library)
            repository = repo
            selection = photos.first?.id
        } catch { self.error = error.localizedDescription; status = "Library unavailable" }
    }
    var photos: [Photo] {
        library.photos.filter { photo in
            let inScope: Bool
            if scope.hasPrefix("project:"), let id = UUID(uuidString: String(scope.dropFirst(8))) { inScope = photo.projectID == id }
            else if scope.hasPrefix("album:"), let id = UUID(uuidString: String(scope.dropFirst(6))) { inScope = photo.albumIDs.contains(id) }
            else { inScope = true }
            return inScope && BrowserFilterRules.includes(rating: photo.rating, flagged: photo.flagged, ratingFilter: ratingFilter, flaggedOnly: scope == "flagged") && (search.isEmpty || [photo.originalName, photo.caption, photo.keywords, photo.camera].joined(separator: " ").localizedCaseInsensitiveContains(search))
        }.sorted { lhs, rhs in sortDescending ? orderedBefore(rhs, lhs) : orderedBefore(lhs, rhs) }
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
        if scope == "flagged" { return "Flagged" }
        if let project = library.projects.first(where: { scope == "project:\($0.id)" }) { return project.name }
        if let album = library.albums.first(where: { scope == "album:\($0.id)" }) { return album.name }
        return "All Photos"
    }
    func save() { do { try repository?.save(library) } catch { self.error = error.localizedDescription } }
    func edit(_ change: (inout Photo) -> Void) {
        guard !busy, let id = selection, let index = library.photos.firstIndex(where: { $0.id == id }) else { return }
        let previous = library.photos[index]
        change(&library.photos[index])
        library.photos[index].rating = RatingRules.clamp(library.photos[index].rating)
        guard library.photos[index] != previous else { return }
        editUndo.registerUndo(withTarget: self) { $0.restore(previous) }
        editUndo.setActionName("Photo Edit")
        save()
    }
    func restore(_ photo: Photo) {
        guard let index = library.photos.firstIndex(where: { $0.id == photo.id }) else { return }
        let previous = library.photos[index]
        editUndo.registerUndo(withTarget: self) { $0.restore(previous) }
        library.photos[index] = photo
        selection = photo.id; compareOriginal = false; tool = .select
        save()
    }
    func rotate(_ turns: Int) {
        compareOriginal = false; tool = .select
        edit { $0.adjustments.quarterTurns = (($0.adjustments.quarterTurns % 4) + turns + 4) % 4; $0.adjustments.crop = nil }
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
        guard let selected else { return }
        liftedAdjustments = LiftedSettings(selected)
        status = "Settings lifted · select another photo and Stamp"
    }
    func stamp() {
        guard let liftedAdjustments, !stampGroups.isEmpty || !stampMetadata.isEmpty else { return }
        compareOriginal = false; tool = .select
        edit { $0 = liftedAdjustments.applying(to: $0, groups: stampGroups, metadata: stampMetadata) }
        status = "Selected settings stamped · original preserved"
    }
    func binding<T>(_ path: WritableKeyPath<Photo, T>, fallback: T) -> Binding<T> {
        Binding(get: { self.selected?[keyPath: path] ?? fallback }, set: { value in self.edit { $0[keyPath: path] = value } })
    }
    func addCollection(_ name: String, project: Bool) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = Collection(name: trimmed)
        if project { library.projects.append(item); scope = "project:\(item.id)" }
        else { library.albums.append(item); scope = "album:\(item.id)" }
        selection = nil; save()
    }
    func importPanel() {
        let panel = NSOpenPanel(); panel.title = "Import photographs — originals will be copied"
        panel.canChooseDirectories = true; panel.canChooseFiles = true; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        importURLs(panel.urls)
    }
    func importURLs(_ urls: [URL]) {
        guard !busy, let repository else { return }
        busy = true; status = "Importing and verifying originals…"
        var snapshot = library
        let projectID = library.projects.first(where: { scope == "project:\($0.id)" })?.id
        let albumID = library.albums.first(where: { scope == "album:\($0.id)" })?.id
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> (Library, Int, Int, [String]) in
                var imported = 0, duplicates = 0, errors: [String] = []
                for url in urls {
                    // Legacy packages must go through the verified-copy recovery action.
                    if ["aplibrary", "aperturelibrary", "photoslibrary", "photolibrary", "app"].contains(url.pathExtension.lowercased()) { errors.append("\(url.lastPathComponent): use legacy recovery for Aperture libraries"); continue }
                    var directory: ObjCBool = false
                    FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                    let files = directory.boolValue ? LibraryRepository.imageFiles(in: url) : [url]
                    for file in files {
                        do {
                            if try repository.importPhoto(file, projectID: projectID, into: &snapshot) {
                                if let albumID { snapshot.photos[snapshot.photos.count - 1].albumIDs.insert(albumID); try repository.save(snapshot) }
                                imported += 1
                            } else { duplicates += 1 }
                        } catch { errors.append("\(file.lastPathComponent): \(error.localizedDescription)") }
                    }
                }
                return (snapshot, imported, duplicates, errors)
            }.value
            library = result.0; selection = photos.last?.id; busy = false
            status = "Imported \(result.1) · duplicates \(result.2) · failed \(result.3.count)"
            if !result.3.isEmpty { error = result.3.prefix(8).joined(separator: "\n") }
        }
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
    func exportPanel() { if selected != nil && !busy { showExportOptions = true } }
    func exportWithOptions(_ options: ExportOptions) {
        guard let photo = selected, let repository, !busy else { return }
        let panel = NSSavePanel()
        let suffix = options.format == .original ? URL(fileURLWithPath: photo.originalName).pathExtension : options.format.suffix
        panel.allowedContentTypes = options.format == .original ? [UTType(filenameExtension: suffix) ?? .data] : [options.format.type]
        panel.nameFieldStringValue = (photo.originalName as NSString).deletingPathExtension + (options.format == .original ? "-original." : "-edited.") + suffix
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
            CommandGroup(replacing: .help) {
                Button("Features & Limits…") { openWindow(id: "features") }
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo Photo Edit") { workspace.editUndo.undo() }.keyboardShortcut("z").disabled(!workspace.editUndo.canUndo || workspace.busy)
                Button("Redo Photo Edit") { workspace.editUndo.redo() }.keyboardShortcut("z", modifiers: [.command, .shift]).disabled(!workspace.editUndo.canRedo || workspace.busy)
            }
            CommandGroup(after: .newItem) {
                Button("Import Photos…", action: workspace.importPanel).keyboardShortcut("i").disabled(workspace.busy || workspace.repository == nil)
                Button("Recover Aperture Originals…", action: workspace.recoverPanel).disabled(workspace.busy || workspace.repository == nil)
                Button("Export Photo…", action: workspace.exportPanel).keyboardShortcut("e", modifiers: [.command, .shift]).disabled(workspace.selected == nil || workspace.busy)
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
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.aperture").font(.system(size: 29, weight: .light)).foregroundStyle(.white).frame(width: 46, height: 46).workspaceGlass(radius: 14)
                    VStack(alignment: .leading) { Text("Isonique").font(.system(size: 22, weight: .semibold, design: .rounded)); Text("PHOTO WORKSPACE").font(.system(size: 9, weight: .medium)).tracking(1.6).foregroundStyle(.secondary) }
                }.padding(20)
                List(selection: $model.scope) {
                    Section("Library") {
                        Label("All Photos", systemImage: "photo.on.rectangle.angled").tag("all")
                        Label("Flagged", systemImage: "flag").tag("flagged")
                    }
                    Section("Projects") {
                        ForEach(model.library.projects) { project in Label(project.name, systemImage: "folder").tag("project:\(project.id)") }
                    }
                    Section("Albums") {
                        ForEach(model.library.albums) { album in Label(album.name, systemImage: "rectangle.stack").tag("album:\(album.id)") }
                    }
                }.listStyle(.sidebar).scrollContentBackground(.hidden)
                HStack {
                    Menu { Button("New Project") { creatingProject = true; showCollection = true }; Button("New Album") { creatingProject = false; showCollection = true } } label: { Image(systemName: "plus"); Text("Create") }
                        .menuStyle(.borderlessButton)
                    Spacer()
                    Text("\(model.library.photos.count) photos").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.background(.ultraThinMaterial).navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) { Text(model.title).font(.title2.weight(.semibold)); Text("\(model.photos.count) photographs").font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    Picker("Rating filter", selection: $model.ratingFilter) { ForEach(RatingFilter.allCases) { filter in Text(filter.label).tag(filter) } }.labelsHidden().frame(width: 165)
                    Picker("View", selection: $model.viewer) { Image(systemName: "square.grid.2x2").tag(false); Image(systemName: "rectangle.bottomthird.inset.filled").tag(true) }.labelsHidden().pickerStyle(.segmented).frame(width: 80)
                }.padding(.horizontal, 22).padding(.vertical, 16)
                Divider().opacity(0.4)
                EditBar()
                Divider().opacity(0.4)
                HSplitView {
                    VStack(spacing: 0) {
                        if model.photos.isEmpty {
                            VStack(spacing: 18) {
                                Image(systemName: "camera.aperture").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(.secondary)
                                Text(model.library.photos.isEmpty ? "A new home for your photographs" : "No photographs in this view").font(.title2)
                                Text("Import into projects. Organise with albums. Keep every original.").foregroundStyle(.secondary)
                                Button(action: model.importPanel) { Label("Import Photographs…", systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if model.viewer, let photo = model.selected, let repo = model.repository, let url = try? repo.originalURL(photo) {
                            PhotoViewer(photo: photo, url: url, original: model.compareOriginal).frame(maxWidth: .infinity, maxHeight: .infinity)
                            ScrollView(.horizontal) { LazyHStack(spacing: 10) { ForEach(model.photos) { photo in photoCell(photo, compact: true) } }.padding(12) }
                                .scrollIndicators(.hidden).frame(height: 128).workspaceGlass(radius: 18).padding(.horizontal, 16).padding(.bottom, 14)
                        } else {
                            ScrollView { LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 16)], spacing: 18) { ForEach(model.photos) { photo in photoCell(photo, compact: false) } }.padding(20) }
                        }
                    }.frame(minWidth: 400).background(Color(white: 0.055))
                    if model.showInspector {
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
            ToolbarItem { Button { openWindow(id: "features") } label: { Label("Features & Limits", systemImage: "questionmark.circle") }.help("See available features and what is still missing") }
            ToolbarItem { Button { withAnimation(.easeInOut(duration: 0.2)) { model.showInspector.toggle() } } label: { Label("Inspector", systemImage: "sidebar.right") }.help("Show or hide inspector") }
            ToolbarItem {
                Menu {
                    Picker("Sort by", selection: $model.sort) { ForEach(PhotoSort.allCases) { Text($0.rawValue).tag($0) } }
                    Toggle("Descending", isOn: $model.sortDescending)
                } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            }
            ToolbarItem { Button(action: model.importPanel) { Label("Import", systemImage: "square.and.arrow.down") } }
            ToolbarItem { Button(action: model.exportPanel) { Label("Export", systemImage: "square.and.arrow.up") }.disabled(model.selected == nil) }
        }
        .sheet(isPresented: $model.showExportOptions) { ExportOptionsView().environmentObject(model) }
        .sheet(isPresented: $showCollection) {
            VStack(alignment: .leading, spacing: 20) {
                Text(creatingProject ? "New Project" : "New Album").font(.title2)
                TextField("Name", text: $collectionName).frame(width: 320).onSubmit(createCollection)
                HStack { Button("Cancel") { showCollection = false }; Spacer(); Button("Create", action: createCollection).buttonStyle(.borderedProminent).disabled(collectionName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(28)
        }
        .alert("Isonique", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("OK") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: model.scope) { _, _ in model.selection = model.photos.first?.id }
        .onChange(of: model.search) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.ratingFilter) { _, _ in if model.selected == nil { model.selection = model.photos.first?.id } }
        .onChange(of: model.selection) { _, _ in model.tool = .select; model.compareOriginal = false }
    }
    func createCollection() { model.addCollection(collectionName, project: creatingProject); collectionName = ""; showCollection = false }
    @ViewBuilder func photoCell(_ photo: Photo, compact: Bool) -> some View {
        if let repo = model.repository, let url = try? repo.originalURL(photo) {
            Button { model.selection = photo.id } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Thumbnail(url: url).frame(height: compact ? 76 : 140).frame(maxWidth: .infinity).background(Color.black.opacity(0.3)).clipped()
                    Text(photo.originalName).font(.caption).lineLimit(1)
                    if !compact { HStack { Text(photo.rating == RatingRules.rejected ? "Rejected" : RatingRules.stars(photo.rating)).foregroundStyle(.orange); Spacer(); if photo.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange) } }.font(.caption).frame(height: 14) }
                }.padding(7).frame(width: compact ? 110 : nil)
                    .background(model.selection == photo.id ? Color.accentColor.opacity(0.18) : Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.selection == photo.id ? Color.accentColor : Color.white.opacity(0.07), lineWidth: model.selection == photo.id ? 2 : 1))
            }.buttonStyle(.plain)
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
            .disabled(model.selected == nil)
    }
    var controls: some View {
        HStack(spacing: 14) {
            tool("Select", icon: "cursorarrow", mode: .select)
            Button { model.rotate(-1) } label: { Label("Left", systemImage: "rotate.left") }.help("Rotate 90° left; clears crop")
            Button { model.rotate(1) } label: { Label("Right", systemImage: "rotate.right") }.help("Rotate 90° right; clears crop")
            Divider().frame(height: 20)
            tool("Crop", icon: "crop", mode: .crop)
            tool("Straighten", icon: "level", mode: .straighten)
            Divider().frame(height: 20)
            Button(action: model.lift) { Label("Lift", systemImage: "eyedropper") }.help("Copy adjustments from this photo")
            Button(action: model.stamp) { Label("Stamp", systemImage: "eyedropper.full") }.disabled(model.liftedAdjustments == nil || (model.stampGroups.isEmpty && model.stampMetadata.isEmpty)).help("Apply the adjustments and metadata selected in Inspector")
            Divider().frame(height: 20)
            Toggle(isOn: $model.compareOriginal) { Label("Original", systemImage: "square.on.square") }.toggleStyle(.button).disabled(model.tool != .select).help("Compare with the untouched original")
            Button { model.editUndo.undo() } label: { Image(systemName: "arrow.uturn.backward") }.disabled(!model.editUndo.canUndo).help("Undo photo edit").accessibilityLabel("Undo photo edit")
            Button { model.editUndo.redo() } label: { Image(systemName: "arrow.uturn.forward") }.disabled(!model.editUndo.canRedo).help("Redo photo edit").accessibilityLabel("Redo photo edit")
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
        .task(id: "\(photo.id)-\(photo.adjustments)-\(original)-\(zoom)-\(model.tool)") {
            var settings = original ? Adjustments() : photo.adjustments
            if model.tool == .crop { settings.crop = nil }
            if model.tool == .crop, let size = try? Renderer.dimensions(url, adjustments: settings) { cropSize = size }
            let maximum: CGFloat? = zoom && model.tool == .select ? nil : 2400
            let result = await Task.detached(priority: .userInitiated) { () -> Result<CGImage, Error> in
                Result { try Renderer.render(url, adjustments: settings, maxDimension: maximum) }
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
                if let photo = model.selected {
                    Text(photo.originalName).font(.headline).textSelection(.enabled)
                    Picker("Inspector section", selection: $tab) {
                        Text("Info").tag("Info")
                        Text("Adjustments").tag("Adjustments")
                        Text("Library").tag("Library")
                    }.pickerStyle(.segmented).labelsHidden()
                    if tab == "Info" { info(photo) }
                    if tab == "Adjustments" { adjustments(photo) }
                    if tab == "Library" { organisation() }
                } else {
                    Text("Select a photograph to view metadata and adjustments.").foregroundStyle(.secondary)
                    Divider()
                    Text("Isonique preserves your originals. Camera RAW support depends on macOS decoders; editing uses Isonique’s own pixel formulas.").font(.caption).foregroundStyle(.secondary)
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
                Toggle("Rejected", isOn: Binding(get: { photo.rating == RatingRules.rejected }, set: { rejected in model.edit { $0.rating = RatingRules.rejectionRating(isRejected: rejected) } }))
                Button("Unrated") { model.edit { $0.rating = RatingRules.unrated } }
            }
            HStack {
                Button("Lower Rating") { model.edit { $0.rating = RatingRules.adjusting($0.rating, by: -1) } }
                    .disabled(photo.rating <= RatingRules.rejected)
                Button("Raise Rating") { model.edit { $0.rating = RatingRules.adjusting($0.rating, by: 1) } }
                    .disabled(photo.rating >= RatingRules.maximum)
            }
            Text("Caption").font(.caption).foregroundStyle(.secondary)
            TextField("Caption", text: model.binding(\.caption, fallback: ""), axis: .vertical)
            Text("Keywords").font(.caption).foregroundStyle(.secondary)
            TextField("Keywords, separated by commas", text: model.binding(\.keywords, fallback: ""))
            Button("Reveal Managed Original") {
                if let repository = model.repository, let url = try? repository.originalURL(photo) {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
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
            adjustment("Contrast", path: \.adjustments.contrast, range: 0.5...1.5, neutral: 1)
            adjustment("Saturation", path: \.adjustments.saturation, range: 0...2, neutral: 1)
            Divider()
            Text("WHITE BALANCE").font(.caption).foregroundStyle(.secondary)
            adjustment("Warmth", path: \.adjustments.warmth, range: -1...1)
            adjustment("Tint", path: \.adjustments.tint, range: -1...1)
            Divider()
            Text("HIGHLIGHTS & SHADOWS").font(.caption).foregroundStyle(.secondary)
            adjustment("Shadows", path: \.adjustments.shadows, range: 0...1)
            adjustment("Highlights", path: \.adjustments.highlights, range: -1...0)
            DisclosureGroup("Crop & Rotation") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack { Button("Rotate Left") { model.rotate(-1) }; Button("Rotate Right") { model.rotate(1) } }
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
            ForEach(model.library.albums) { album in
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
