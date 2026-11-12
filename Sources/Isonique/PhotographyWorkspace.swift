import AppKit
import CoreGraphics
import SwiftUI
import IsoniqueCore

enum PhotographyWorkspaceMode: String, Codable, CaseIterable, Identifiable {
    case editing = "Editing"
    case culling = "Culling"
    case compare = "Compare"

    var id: String { rawValue }
}

struct PhotographyWorkspaceLayout: Codable, Equatable {
    var browser: Bool
    var filmstrip: Bool
    var inspector: Bool
    var toolbar: Bool

    static func defaultValue(for mode: PhotographyWorkspaceMode) -> Self {
        switch mode {
        case .editing: return .init(browser: false, filmstrip: true, inspector: true, toolbar: true)
        case .culling: return .init(browser: true, filmstrip: false, inspector: false, toolbar: true)
        case .compare: return .init(browser: false, filmstrip: true, inspector: false, toolbar: true)
        }
    }
}

enum PhotographyWorkspacePanel: String, CaseIterable {
    case browser = "Browser"
    case filmstrip = "Filmstrip"
    case inspector = "Inspector"
    case toolbar = "Toolbar"
}

enum PhotographyWorkspaceFocus: String, CaseIterable, Hashable {
    case viewer = "Viewer"
    case browser = "Browser"
    case filmstrip = "Filmstrip"
    case inspector = "Inspector"
    case toolbar = "Toolbar"
}

enum PhotographyWorkspaceCommand: Equatable {
    case selectMode(PhotographyWorkspaceMode)
    case togglePanel(PhotographyWorkspacePanel)
    case cycleFocus
}

struct PhotographyWorkspacePreferences: Codable, Equatable {
    static let key = "photography.workspace.layouts.v1"

    var mode: PhotographyWorkspaceMode = .editing
    var editing = PhotographyWorkspaceLayout.defaultValue(for: .editing)
    var culling = PhotographyWorkspaceLayout.defaultValue(for: .culling)
    var compare = PhotographyWorkspaceLayout.defaultValue(for: .compare)

    func layout(for mode: PhotographyWorkspaceMode) -> PhotographyWorkspaceLayout {
        switch mode {
        case .editing: return editing
        case .culling: return culling
        case .compare: return compare
        }
    }

    mutating func set(_ layout: PhotographyWorkspaceLayout, for mode: PhotographyWorkspaceMode) {
        switch mode {
        case .editing: editing = layout
        case .culling: culling = layout
        case .compare: compare = layout
        }
    }

    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: key),
              let preferences = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        return preferences
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }
}

struct PhotographyDisplayDescriptor: Equatable, Identifiable {
    let id: CGDirectDisplayID
    let name: String
    let frame: CGRect
    let backingScale: CGFloat
    let colorSpaceName: String?
    let iccProfile: Data?

    var maximumPixelDimension: CGFloat {
        max(frame.width, frame.height) * backingScale
    }
}

enum PhotographyDisplayPolicy {
    static func secondary(from screens: [PhotographyDisplayDescriptor],
                          primaryID: CGDirectDisplayID?) -> PhotographyDisplayDescriptor? {
        guard screens.count > 1 else { return nil }
        return screens.first { $0.id != primaryID } ?? screens.dropFirst().first
    }
}

extension PhotographyDisplayDescriptor {
    init(screen: NSScreen) {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        id = number.map { CGDirectDisplayID($0.uint32Value) } ?? 0
        name = screen.localizedName
        frame = screen.frame
        backingScale = screen.backingScaleFactor
        colorSpaceName = screen.colorSpace?.localizedName
        iccProfile = screen.colorSpace?.iccProfileData
    }
}

struct SecondaryViewerRequest: Equatable {
    let photoID: UUID
    let filename: String
    let referencedPath: String?
    let adjustments: Adjustments
    let revision: Int
    let maximum: CGFloat
    let proofProfile: Data?

    init(photo: Photo, revision: Int, display: PhotographyDisplayDescriptor,
         proofProfile: Data?) {
        photoID = photo.id
        filename = photo.filename
        referencedPath = photo.referencedPath
        adjustments = photo.adjustments
        self.revision = revision
        maximum = display.maximumPixelDimension
        self.proofProfile = proofProfile
    }
}

enum SecondaryViewerLoader {
    static func load(photo: Photo, request: SecondaryViewerRequest,
                     repository: LibraryRepository, cache: ViewerRenderCache) async throws -> ViewerImage {
        try Task.checkCancellation()
        let url = try repository.availableOriginalURL(photo)
        let frame = try await cache.frame(url: url, adjustments: request.adjustments,
                                          maximum: request.maximum, revision: request.revision)
        try Task.checkCancellation()
        return try await ViewerImage.prepare(frame.image, proofProfile: request.proofProfile)
    }
}

@MainActor
final class SecondaryDisplayViewerController: NSObject, NSWindowDelegate {
    weak var workspace: Workspace?
    private(set) var window: NSWindow?

    init(workspace: Workspace) {
        self.workspace = workspace
    }

    var availableDisplay: NSScreen? {
        let primaryID = workspace?.photographyWindow?.screen.map(PhotographyDisplayDescriptor.init)?.id
        let descriptors = NSScreen.screens.map(PhotographyDisplayDescriptor.init)
        guard let selected = PhotographyDisplayPolicy.secondary(from: descriptors, primaryID: primaryID) else { return nil }
        return NSScreen.screens.first { PhotographyDisplayDescriptor(screen: $0).id == selected.id }
    }

    func show() {
        guard let workspace, let screen = availableDisplay else { return }
        if let window {
            installContent(in: window, for: screen, workspace: workspace)
            configure(window, for: screen)
            window.orderFrontRegardless()
            workspace.secondaryViewerVisible = true
            return
        }
        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false, screen: screen)
        window.title = "Isonique Secondary Viewer"
        window.backgroundColor = .black
        window.isOpaque = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.delegate = self
        installContent(in: window, for: screen, workspace: workspace)
        configure(window, for: screen)
        self.window = window
        window.orderFrontRegardless()
        workspace.secondaryViewerVisible = true
    }

    func close() {
        window?.orderOut(nil)
        workspace?.secondaryViewerVisible = false
    }

    func toggle() {
        if workspace?.secondaryViewerVisible == true { close() } else { show() }
    }

    private func configure(_ window: NSWindow, for screen: NSScreen) {
        window.colorSpace = screen.colorSpace
        window.setFrame(screen.frame, display: true)
    }

    private func installContent(in window: NSWindow, for screen: NSScreen, workspace: Workspace) {
        window.contentViewController = NSHostingController(
            rootView: SecondaryDisplayViewer(display: PhotographyDisplayDescriptor(screen: screen))
                .environmentObject(workspace)
        )
    }

    func windowWillClose(_ notification: Notification) {
        workspace?.secondaryViewerVisible = false
    }
}

private struct SecondaryDisplayViewer: View {
    @EnvironmentObject private var model: Workspace
    let display: PhotographyDisplayDescriptor
    @State private var image: ViewerImage?
    @State private var failure: String?

    private var photo: Photo? {
        let id = model.selection ?? model.comparisonID
        return id.flatMap { id in model.library.activePhotos.first { $0.id == id } }
    }

    private var request: SecondaryViewerRequest? {
        photo.map {
            SecondaryViewerRequest(photo: $0, revision: model.originalStatusRevision,
                                   display: display,
                                   proofProfile: model.proofEnabled ? model.proofProfile : nil)
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(decorative: image.display, scale: 1)
                    .resizable().aspectRatio(image.size, contentMode: .fit)
            } else if let failure {
                ContentUnavailableView("Image unavailable", systemImage: "exclamationmark.triangle",
                                       description: Text(failure))
            } else if photo == nil {
                ContentUnavailableView("No photo selected", systemImage: "photo")
            } else {
                ProgressView()
            }
        }
        .overlay(alignment: .topLeading) {
            if let photo {
                HStack(spacing: 10) {
                    Text(photo.displayName).lineLimit(1)
                    Text(display.name).foregroundStyle(.secondary)
                    if model.proofEnabled { Text("RGB Proof").foregroundStyle(.yellow) }
                }
                .font(.caption).padding(10).background(.black.opacity(0.72), in: Capsule()).padding(16)
            }
        }
        .task(id: request) {
            image = nil
            failure = nil
            guard let photo, let request, let repository = model.repository else { return }
            do {
                let loaded = try await SecondaryViewerLoader.load(photo: photo, request: request,
                    repository: repository, cache: model.viewerRenderCache)
                try Task.checkCancellation()
                image = loaded
            } catch {
                if !Task.isCancelled { failure = error.localizedDescription }
            }
        }
    }
}

struct PhotographyWindowReader: NSViewRepresentable {
    let resolved: @MainActor (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { resolved(window) } }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { if let window = view.window { resolved(window) } }
    }
}

struct PhotographyWorkspaceInteractionModifier: ViewModifier {
    @ObservedObject var model: Workspace
    @Binding var columnVisibility: NavigationSplitViewVisibility
    var focusedPanel: FocusState<PhotographyWorkspaceFocus?>.Binding

    func body(content: Content) -> some View {
        content
            .onExitCommand {
                if model.isPhotographyFullScreen { model.togglePhotographyFullScreen() }
                else { model.exitViewer() }
            }
            .onChange(of: model.viewer) { _, viewing in
                if viewing { model.photographyFocus = .viewer }
                else { model.tool = .select; model.compareOriginal = false; model.stopComparison() }
            }
            .onChange(of: model.photographyFocus) { _, focus in
                focusedPanel.wrappedValue = focus
            }
            .onChange(of: focusedPanel.wrappedValue) { _, focus in
                if let focus, model.photographyFocus != focus { model.photographyFocus = focus }
            }
            .onChange(of: model.isPhotographyFullScreen) { _, active in
                columnVisibility = active ? .detailOnly : .all
            }
    }
}

extension Workspace {
    func restorePhotographyWorkspacePreferences() {
        let stored = PhotographyWorkspacePreferences.load(from: preferences)
        photographyWorkspacePreferences = stored
        photographyMode = stored.mode
        photographyLayout = stored.layout(for: stored.mode)
        showInspector = photographyLayout.inspector
        photographyFocus = photographyLayout.browser ? .browser : .viewer
    }

    func performPhotographyWorkspaceCommand(_ command: PhotographyWorkspaceCommand) {
        switch command {
        case .selectMode(let mode): selectPhotographyMode(mode)
        case .togglePanel(let panel): togglePhotographyPanel(panel)
        case .cycleFocus: cyclePhotographyFocus()
        }
    }

    func selectPhotographyMode(_ mode: PhotographyWorkspaceMode) {
        photographyWorkspacePreferences.set(photographyLayout, for: photographyMode)
        photographyMode = mode
        photographyWorkspacePreferences.mode = mode
        photographyLayout = photographyWorkspacePreferences.layout(for: mode)
        showInspector = photographyLayout.inspector
        switch mode {
        case .editing:
            if selected != nil { viewer = true }
        case .culling:
            showBrowser()
        case .compare:
            if comparisonID == nil { startComparison() }
        }
        photographyFocus = photographyLayout.browser ? .browser : .viewer
        persistPhotographyWorkspacePreferences()
        syncPhotographyWindowChrome()
    }

    func togglePhotographyPanel(_ panel: PhotographyWorkspacePanel) {
        switch panel {
        case .browser: photographyLayout.browser.toggle()
        case .filmstrip: photographyLayout.filmstrip.toggle()
        case .inspector:
            photographyLayout.inspector.toggle()
            showInspector = photographyLayout.inspector
        case .toolbar: photographyLayout.toolbar.toggle()
        }
        if !visiblePhotographyFocus.contains(photographyFocus) { photographyFocus = .viewer }
        persistPhotographyWorkspacePreferences()
        syncPhotographyWindowChrome()
    }

    var visiblePhotographyFocus: [PhotographyWorkspaceFocus] {
        var result: [PhotographyWorkspaceFocus] = [.viewer]
        if photographyLayout.browser { result.append(.browser) }
        if photographyLayout.filmstrip && viewer { result.append(.filmstrip) }
        if photographyLayout.inspector { result.append(.inspector) }
        if photographyLayout.toolbar { result.append(.toolbar) }
        return result
    }

    func cyclePhotographyFocus() {
        let visible = visiblePhotographyFocus
        let index = visible.firstIndex(of: photographyFocus) ?? -1
        photographyFocus = visible[(index + 1) % visible.count]
    }

    func attachPhotographyWindow(_ window: NSWindow) {
        guard photographyWindow !== window else { return }
        for observer in photographyWindowObservers { NotificationCenter.default.removeObserver(observer) }
        photographyWindowObservers = [
            NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification,
                object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    MainActor.assumeIsolated { self.setPhotographyFullScreen(true, window: window) }
                },
            NotificationCenter.default.addObserver(forName: NSWindow.didExitFullScreenNotification,
                object: window, queue: .main) { [weak self, weak window] _ in
                    guard let self, let window else { return }
                    MainActor.assumeIsolated { self.setPhotographyFullScreen(false, window: window) }
                }
        ]
        photographyWindow = window
        isPhotographyFullScreen = window.styleMask.contains(.fullScreen)
        syncPhotographyWindowChrome()
    }

    func togglePhotographyFullScreen() {
        guard let window = photographyWindow else { return }
        window.toggleFullScreen(nil)
    }

    func setPhotographyFullScreen(_ active: Bool, window: NSWindow) {
        guard photographyWindow === window else { return }
        isPhotographyFullScreen = active
        if active { selectPhotographyMode(photographyMode) }
        syncPhotographyWindowChrome()
    }

    func syncPhotographyWindowChrome() {
        photographyWindow?.toolbar?.isVisible = photographyLayout.toolbar
    }

    var secondaryViewerAvailable: Bool { secondaryDisplayController.availableDisplay != nil }

    func toggleSecondaryViewer() {
        secondaryDisplayController.toggle()
    }

    private func persistPhotographyWorkspacePreferences() {
        photographyWorkspacePreferences.mode = photographyMode
        photographyWorkspacePreferences.set(photographyLayout, for: photographyMode)
        photographyWorkspacePreferences.save(to: preferences)
    }
}
