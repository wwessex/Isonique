import SwiftUI
import IsoniqueCore

struct ClippingSettings: Equatable {
    static let highlightRange = 50...100
    static let shadowRange = 0...50
    static let defaultHighlightThreshold = 100
    static let defaultShadowThreshold = 0

    var highlights = false
    var shadows = false
    var highlightThreshold = Self.defaultHighlightThreshold
    var shadowThreshold = Self.defaultShadowThreshold

    var enabled: Bool { highlights || shadows }
    var both: Bool {
        get { highlights && shadows }
        set { highlights = newValue; shadows = newValue }
    }

    init() {}

    init(preferences: UserDefaults) {
        highlights = preferences.bool(forKey: "clipping.highlights")
        shadows = preferences.bool(forKey: "clipping.shadows")
        highlightThreshold = Self.highlightRange.clamp(
            preferences.object(forKey: "clipping.highlightThreshold") as? Int ?? Self.defaultHighlightThreshold)
        shadowThreshold = Self.shadowRange.clamp(
            preferences.object(forKey: "clipping.shadowThreshold") as? Int ?? Self.defaultShadowThreshold)
    }

    var thresholdsAreDefault: Bool {
        highlightThreshold == Self.defaultHighlightThreshold && shadowThreshold == Self.defaultShadowThreshold
    }

    mutating func resetThresholds() {
        highlightThreshold = Self.defaultHighlightThreshold
        shadowThreshold = Self.defaultShadowThreshold
    }

    func save(to preferences: UserDefaults) {
        preferences.set(highlights, forKey: "clipping.highlights")
        preferences.set(shadows, forKey: "clipping.shadows")
        preferences.set(highlightThreshold, forKey: "clipping.highlightThreshold")
        preferences.set(shadowThreshold, forKey: "clipping.shadowThreshold")
    }
}

private extension ClosedRange<Int> {
    func clamp(_ value: Int) -> Int { Swift.min(upperBound, Swift.max(lowerBound, value)) }
}

enum ClippingTint {
    case highlights, shadows, both

    var rgb: (red: Int, green: Int, blue: Int) {
        switch self {
        case .highlights: (255, 32, 32)
        case .shadows: (32, 112, 255)
        case .both: (235, 32, 235)
        }
    }

    var color: Color {
        let (red, green, blue) = rgb
        return Color(red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
    }
}

enum ClippingOverlay {
    /// Classify the edited sRGB preview before proofing or scaling it for the window.
    /// This transparent layer belongs to the Viewer and never enters the export renderer.
    static func make(from image: CGImage, settings: ClippingSettings) throws -> CGImage? {
        guard settings.enabled else { return nil }
        try Task.checkCancellation()
        let width = image.width, height = image.height
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: bitmapInfo),
              let data = context.data else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let highlightThreshold = ClippingSettings.highlightRange.clamp(settings.highlightThreshold)
        let shadowThreshold = ClippingSettings.shadowRange.clamp(settings.shadowThreshold)
        for offset in stride(from: 0, to: width * height * 4, by: 4) {
            if offset.isMultiple(of: 65_536) { try Task.checkCancellation() }
            let alpha = Int(pixels[offset + 3])
            guard alpha > 0 else { continue }
            let red = Int(pixels[offset]), green = Int(pixels[offset + 1]), blue = Int(pixels[offset + 2])
            // Compare premultiplied channels against alpha-scaled thresholds, without division or rounding.
            let hot = settings.highlights && max(red, green, blue) * 100 >= alpha * highlightThreshold
            let cold = settings.shadows && min(red, green, blue) * 100 <= alpha * shadowThreshold
            if hot || cold {
                let (red, green, blue) = (hot && cold ? ClippingTint.both : hot ? .highlights : .shadows).rgb
                let opacity = (alpha * 166 + 127) / 255
                pixels[offset] = UInt8((red * opacity + 127) / 255)
                pixels[offset + 1] = UInt8((green * opacity + 127) / 255)
                pixels[offset + 2] = UInt8((blue * opacity + 127) / 255)
                pixels[offset + 3] = UInt8(opacity)
            } else {
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = 0
            }
        }
        return context.makeImage()
    }
}

struct ViewerImage {
    let rendered: CGImage
    let display: CGImage
    var size: CGSize { CGSize(width: rendered.width, height: rendered.height) }

    init(_ rendered: CGImage, proofProfile: Data?) throws {
        self.rendered = rendered
        display = try proofProfile.map { try Renderer.proof(rendered, profile: $0) } ?? rendered
    }

    static func prepare(_ rendered: CGImage, proofProfile: Data?) async throws -> ViewerImage {
        try Task.checkCancellation()
        guard let proofProfile else { return try ViewerImage(rendered, proofProfile: nil) }
        let proof = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            return try ViewerImage(rendered, proofProfile: proofProfile)
        }
        let result = await withTaskCancellationHandler {
            await proof.result
        } onCancel: { proof.cancel() }
        try Task.checkCancellation()
        return try result.get()
    }
}

struct ClippingPreview: View {
    @EnvironmentObject private var model: Workspace
    let image: ViewerImage
    @State private var overlay: (request: Request, image: CGImage)?

    private struct Request: Equatable {
        let image: CGImage
        let settings: ClippingSettings

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.image === rhs.image && lhs.settings == rhs.settings
        }
    }

    var body: some View {
        let request = model.clipping.enabled ? Request(image: image.rendered, settings: model.clipping) : nil
        Image(image.display, scale: 1, label: Text("Photo preview")).resizable()
            .overlay {
                if let request, let overlay, overlay.request == request {
                    Image(decorative: overlay.image, scale: 1).resizable()
                        .allowsHitTesting(false)
                }
            }
            .task(id: request) {
                overlay = nil
                guard let request else { return }
                let task = Task.detached(priority: .userInitiated) {
                    try ClippingOverlay.make(from: request.image, settings: request.settings)
                }
                let result = await withTaskCancellationHandler {
                    await task.result
                } onCancel: { task.cancel() }
                guard !Task.isCancelled, case .success(let mask?) = result else { return }
                overlay = (request, mask)
            }
    }
}

struct ClippingLegend: View {
    let settings: ClippingSettings

    var body: some View {
        HStack(spacing: 10) {
            if settings.highlights { mark("Highlights", .highlights) }
            if settings.shadows { mark("Shadows", .shadows) }
            if settings.both { mark("Both", .both) }
        }.font(.caption)
        .accessibilityElement(children: .combine)
    }

    private func mark(_ title: String, _ tint: ClippingTint) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: "circle.fill").foregroundStyle(tint.color).imageScale(.small)
        }
    }
}

struct ClippingSettingsSection: View {
    @EnvironmentObject private var model: Workspace

    var body: some View {
        Section("Clipping Warnings") {
            threshold("Highlights", value: $model.clipping.highlightThreshold, range: ClippingSettings.highlightRange)
            threshold("Shadows", value: $model.clipping.shadowThreshold, range: ClippingSettings.shadowRange)
            Button("Reset Thresholds") { model.clipping.resetThresholds() }
                .disabled(model.clipping.thresholdsAreDefault)
            Text("Warn when any rendered sRGB channel reaches either threshold. Turn warnings on from the View menu.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func threshold(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        let slider = Binding(get: { Double(value.wrappedValue) }, set: { value.wrappedValue = Int($0) })
        return LabeledContent {
            HStack {
                Slider(value: slider, in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .accessibilityLabel(title + " threshold")
                    .accessibilityValue(Text(Double(value.wrappedValue) / 100, format: .percent))
                Text(Double(value.wrappedValue) / 100, format: .percent)
                    .monospacedDigit().frame(width: 42, alignment: .trailing).accessibilityHidden(true)
            }
        } label: {
            Text(title)
        }
    }
}
