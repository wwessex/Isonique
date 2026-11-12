import AppKit
import SwiftUI

enum ComparisonSide { case reference, selected }

struct ComparisonNavigation: Equatable {
    var scale: CGFloat?
    var center = CGPoint(x: 0.5, y: 0.5)

    mutating func toggleActualPixels() {
        scale = ViewerZoom.toggled(scale)
        if scale == nil { center = CGPoint(x: 0.5, y: 0.5) }
    }

    mutating func magnify(from base: CGFloat?, by magnification: CGFloat) {
        scale = ViewerZoom.magnified(from: base, by: magnification)
        if scale == nil { center = CGPoint(x: 0.5, y: 0.5) }
    }

    mutating func moveCenter(to point: CGPoint) {
        guard point.x.isFinite, point.y.isFinite else { return }
        center = CGPoint(x: min(1, max(0, point.x)), y: min(1, max(0, point.y)))
    }
}

struct ComparisonNavigationPair: Equatable {
    var synchronized = true
    var reference = ComparisonNavigation()
    var selected = ComparisonNavigation()

    subscript(side: ComparisonSide) -> ComparisonNavigation {
        switch side {
        case .reference: reference
        case .selected: selected
        }
    }

    mutating func update(_ value: ComparisonNavigation, for side: ComparisonSide) {
        switch side {
        case .reference: reference = value
        case .selected: selected = value
        }
        if synchronized {
            reference = value
            selected = value
        }
    }

    mutating func setSynchronized(_ enabled: Bool) {
        synchronized = enabled
        if enabled { selected = reference }
    }
}

enum ComparisonViewportGeometry {
    static func normalizedCenter(origin: CGPoint, visibleSize: CGSize,
                                 imageSize: CGSize) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGPoint(x: 0.5, y: 0.5)
        }
        return CGPoint(x: min(1, max(0, (origin.x + visibleSize.width / 2) / imageSize.width)),
                       y: min(1, max(0, (origin.y + visibleSize.height / 2) / imageSize.height)))
    }

    static func origin(center: CGPoint, visibleSize: CGSize, imageSize: CGSize) -> CGPoint {
        let maximumX = max(0, imageSize.width - visibleSize.width)
        let maximumY = max(0, imageSize.height - visibleSize.height)
        return CGPoint(x: min(maximumX, max(0, center.x * imageSize.width - visibleSize.width / 2)),
                       y: min(maximumY, max(0, center.y * imageSize.height - visibleSize.height / 2)))
    }
}

struct ComparisonMagnificationSession {
    private(set) var active = false
    private(set) var base: CGFloat?
    private(set) var factor: CGFloat = 1

    mutating func sample(current: CGFloat?, delta: CGFloat, began: Bool, ended: Bool)
        -> (base: CGFloat?, factor: CGFloat) {
        if began || !active {
            active = true
            base = current
            factor = 1
        }
        if delta.isFinite { factor *= max(0.01, 1 + delta) }
        let result = (base, factor)
        if ended {
            active = false
            base = nil
            factor = 1
        }
        return result
    }
}

@MainActor
struct ComparisonViewport: NSViewRepresentable {
    let image: ViewerImage
    let model: Workspace
    let label: String
    @Binding var navigation: ComparisonNavigation

    func makeCoordinator() -> Coordinator { Coordinator(navigation: $navigation) }

    func makeNSView(context: Context) -> ComparisonScrollView {
        let view = ComparisonScrollView()
        view.navigationChanged = context.coordinator.receive
        return view
    }

    func updateNSView(_ view: ComparisonScrollView, context: Context) {
        context.coordinator.navigation = $navigation
        view.navigationChanged = context.coordinator.receive
        view.update(image: image, model: model, label: label)
        view.apply(navigation)
    }

    final class Coordinator {
        var navigation: Binding<ComparisonNavigation>

        init(navigation: Binding<ComparisonNavigation>) {
            self.navigation = navigation
        }

        func receive(_ value: ComparisonNavigation) {
            guard navigation.wrappedValue != value else { return }
            navigation.wrappedValue = value
        }
    }
}

@MainActor
private struct ComparisonImageContent: View {
    @ObservedObject var model: Workspace
    let image: ViewerImage
    let label: String

    var body: some View {
        ClippingPreview(image: image).environmentObject(model)
            .accessibilityLabel(label)
    }
}

@MainActor
final class ComparisonScrollView: NSScrollView {
    var navigationChanged: ((ComparisonNavigation) -> Void)?
    private var hostingView: NSHostingView<AnyView>?
    private var imageSize = CGSize(width: 1, height: 1)
    private var navigation = ComparisonNavigation()
    private var applying = false
    private var magnificationSession = ComparisonMagnificationSession()
    private var lastViewportSize = CGSize.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        drawsBackground = false
        borderType = .noBorder
        allowsMagnification = true
        autohidesScrollers = true
        hasHorizontalScroller = true
        hasVerticalScroller = true
        contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(boundsDidChange(_:)),
            name: NSView.boundsDidChangeNotification, object: contentView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func update(image: ViewerImage, model: Workspace, label: String) {
        imageSize = image.size
        let root = AnyView(ComparisonImageContent(model: model, image: image, label: label))
        if let hostingView {
            hostingView.rootView = root
            hostingView.frame = CGRect(origin: .zero, size: imageSize)
        } else {
            let hosting = NSHostingView(rootView: root)
            hosting.frame = CGRect(origin: .zero, size: imageSize)
            hosting.autoresizingMask = []
            documentView = hosting
            hostingView = hosting
        }
    }

    func apply(_ navigation: ComparisonNavigation) {
        self.navigation = navigation
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        applying = true
        defer { applying = false }
        let fit = fitScale
        minMagnification = min(fit, ViewerZoom.minimumScale)
        maxMagnification = ViewerZoom.maximumScale
        let requested = navigation.scale ?? fit
        let bounded = min(maxMagnification, max(minMagnification, requested))
        if abs(magnification - bounded) > 0.000_1 { magnification = bounded }
        hasHorizontalScroller = navigation.scale != nil
        hasVerticalScroller = navigation.scale != nil
        let origin = ComparisonViewportGeometry.origin(center: navigation.center,
            visibleSize: contentView.bounds.size, imageSize: imageSize)
        contentView.scroll(to: origin)
        reflectScrolledClipView(contentView)
    }

    override func layout() {
        super.layout()
        let size = contentSize
        guard size != lastViewportSize else { return }
        lastViewportSize = size
        apply(navigation)
    }

    override func magnify(with event: NSEvent) {
        let sample = magnificationSession.sample(current: navigation.scale,
            delta: event.magnification, began: event.phase == .began,
            ended: event.phase == .ended || event.phase == .cancelled)
        var updated = navigation
        updated.magnify(from: sample.base, by: sample.factor)
        navigationChanged?(updated)
    }

    private var fitScale: CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        return max(0.001, min(contentSize.width / imageSize.width,
                              contentSize.height / imageSize.height))
    }

    @objc private func boundsDidChange(_ notification: Notification) {
        reportPan()
    }

    private func reportPan() {
        guard !applying, navigation.scale != nil else { return }
        var updated = navigation
        updated.moveCenter(to: ComparisonViewportGeometry.normalizedCenter(
            origin: contentView.bounds.origin, visibleSize: contentView.bounds.size,
            imageSize: imageSize))
        navigationChanged?(updated)
    }
}
