import SwiftUI
import AppKit
import IsoniqueCore

private extension LocalBrushAdjustment {
    var guideColor: Color {
        switch self {
        case .dodge: return .yellow
        case .burn: return .blue
        case .saturation: return .pink
        case .definition: return .mint
        case .sharpening: return .orange
        case .noiseReduction: return .purple
        case .contrast: return .cyan
        case .blur: return .gray
        }
    }
}

extension Workspace {
    var canBrush: Bool {
        guard !busy, !batchMode, !isViewingTrash, let selected else { return false }
        return isOriginalAvailable(selected) == true
    }

    func chooseBrush(_ adjustment: LocalBrushAdjustment) {
        guard canBrush else { return }
        brushAdjustment = adjustment
        chooseTool(.brush)
    }

    func applyBrushStroke(_ stroke: LocalBrushStroke, to id: UUID) {
        guard tool == .brush, !batchMode, selection == id, stroke.isValid else { return }
        edit { photo in
            if stroke.erasing && !photo.adjustments.localBrushes.contains(where: {
                $0.adjustment == stroke.adjustment && !$0.erasing
            }) { return }
            photo.adjustments.localBrushes.append(stroke)
        }
    }

    func clearBrushMask(_ adjustment: LocalBrushAdjustment) {
        guard !batchMode else { return }
        edit {
            $0.adjustments.localBrushes.removeAll { $0.adjustment == adjustment }
            $0.adjustments.localBrushMaskSettings.removeValue(forKey: adjustment)
        }
    }

    func setBrushMaskOpacity(_ opacity: Double, for adjustment: LocalBrushAdjustment) {
        guard !batchMode, selected?.adjustments.localBrushes.contains(where: {
            $0.adjustment == adjustment && !$0.erasing
        }) == true else { return }
        let value = opacity.isFinite ? min(1, max(0, opacity)) : 1
        edit {
            var settings = $0.adjustments.localBrushSettings(for: adjustment)
            guard settings.opacity != value else { return }
            settings.opacity = value
            if settings.isNeutral { $0.adjustments.localBrushMaskSettings.removeValue(forKey: adjustment) }
            else { $0.adjustments.localBrushMaskSettings[adjustment] = settings }
        }
    }

    func invertBrushMask(_ adjustment: LocalBrushAdjustment) {
        guard !batchMode, selected?.adjustments.localBrushes.contains(where: {
            $0.adjustment == adjustment && !$0.erasing
        }) == true else { return }
        edit {
            var settings = $0.adjustments.localBrushSettings(for: adjustment)
            settings.inverted.toggle()
            if settings.isNeutral { $0.adjustments.localBrushMaskSettings.removeValue(forKey: adjustment) }
            else { $0.adjustments.localBrushMaskSettings[adjustment] = settings }
        }
    }
}

struct BrushControls: View {
    @Binding var adjustment: LocalBrushAdjustment
    @Binding var erasing: Bool
    @Binding var size: Double
    @Binding var softness: Double
    @Binding var strength: Double
    @Binding var edgeAware: Bool
    @Binding var showMask: Bool
    let hasMask: Bool
    let maskOpacity: Double
    let maskInverted: Bool
    let setOpacity: (Double) -> Void
    let invert: () -> Void
    let reset: () -> Void
    let done: () -> Void
    @State private var opacity = 100.0
    @State private var editingOpacity = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Brush adjustment", selection: $adjustment) {
                    ForEach(LocalBrushAdjustment.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.menu).frame(width: 180)
                Toggle("Erase", isOn: $erasing).toggleStyle(.button).help("Erase from the selected mask")
                Toggle("Edge Aware", isOn: $edgeAware).toggleStyle(.button)
                    .help("Protect edges whose luminance differs from the start of the stroke")
                Toggle("Show Mask", isOn: $showMask).toggleStyle(.button)
                    .disabled(!hasMask).help("Show the selected adjustment mask over the Viewer only")
                Spacer()
                Button(maskInverted ? "Uninvert Mask" : "Invert Mask", action: invert).disabled(!hasMask)
                Button("Reset Mask", action: reset).disabled(!hasMask)
                Button("Done", action: done)
            }
            HStack(spacing: 10) {
                slider("Size", value: $size, range: 1...50)
                slider("Softness", value: $softness, range: 0...100)
                slider("Strength", value: $strength, range: 1...100)
                VStack(spacing: 2) {
                    HStack {
                        Text("Mask Opacity")
                        Spacer(minLength: 2)
                        Text(opacity, format: .number.precision(.fractionLength(0))) + Text("%")
                    }.monospacedDigit().foregroundStyle(.secondary)
                    Slider(value: $opacity, in: 0...100, step: 1) { editing in
                        editingOpacity = editing
                        if !editing { setOpacity(opacity / 100) }
                    }.disabled(!hasMask).accessibilityLabel("Mask opacity")
                }
            }
        }.font(.caption)
            .onAppear { opacity = maskOpacity * 100 }
            .onChange(of: maskOpacity) { _, value in
                if !editingOpacity { opacity = value * 100 }
            }
    }

    private func slider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(name)
                Spacer(minLength: 2)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(0))) + Text("%")
            }.monospacedDigit().foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1).accessibilityLabel(name)
        }
    }
}

struct BrushCanvas: View {
    let image: ViewerImage
    let geometry: PhotoGeometry
    let adjustment: LocalBrushAdjustment
    let erasing: Bool
    let radius: Double
    let softness: Double
    let strength: Double
    let edgeAware: Bool
    let overlay: CGImage?
    let showMask: Bool
    let commit: (LocalBrushStroke) -> Void
    @State private var hover: CGPoint?
    @State private var draft: Draft?

    private struct Draft {
        let adjustment: LocalBrushAdjustment
        let erasing: Bool
        let radius: Double
        let softness: Double
        let strength: Double
        let edgeAware: Bool
        var points: [CGPoint] = []
    }

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let sourceEdge = min(geometry.sourceSize.width, geometry.sourceSize.height)
            let diameter = max(2, 2 * (draft?.radius ?? radius) * sourceEdge * scale)
            ZStack(alignment: .topLeading) {
                ClippingPreview(image: image).frame(width: size.width, height: size.height)
                if showMask, let overlay {
                    Image(decorative: overlay, scale: 1).resizable()
                        .frame(width: size.width, height: size.height).allowsHitTesting(false)
                }
                if let draft, let first = draft.points.first {
                    let color: Color = draft.erasing ? .white : draft.adjustment.guideColor
                    Path { path in
                        path.move(to: first)
                        for point in draft.points.dropFirst() { path.addLine(to: point) }
                        if draft.points.count == 1 { path.addLine(to: CGPoint(x: first.x + 0.01, y: first.y)) }
                    }.stroke(color.opacity(0.28), style: StrokeStyle(lineWidth: diameter, lineCap: .round, lineJoin: .round))
                        .allowsHitTesting(false)
                }
                if let point = draft?.points.last ?? hover {
                    Circle().strokeBorder(.black.opacity(0.75), lineWidth: 2)
                        .overlay { Circle().strokeBorder(.white, lineWidth: 1) }
                        .frame(width: diameter, height: diameter).position(point).allowsHitTesting(false)
                }
            }.frame(width: size.width, height: size.height).clipped().contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let point): hover = point
                    case .ended: hover = nil
                    }
                }
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    if draft == nil {
                        draft = Draft(adjustment: adjustment, erasing: erasing, radius: radius,
                                      softness: softness, strength: strength, edgeAware: edgeAware,
                                      points: [clamp(drag.startLocation, to: size)])
                    }
                    let point = clamp(drag.location, to: size)
                    if let last = draft?.points.last, hypot(point.x - last.x, point.y - last.y) >= 1.5 {
                        draft?.points.append(point)
                    }
                }.onEnded { drag in
                    guard var completed = draft else { return }
                    draft = nil
                    let end = clamp(drag.location, to: size)
                    if completed.points.last != end { completed.points.append(end) }
                    let points = Self.sourcePoints(completed.points, displayedSize: size, geometry: geometry)
                    commit(LocalBrushStroke(adjustment: completed.adjustment, erasing: completed.erasing,
                                            radius: completed.radius, softness: completed.softness,
                                            strength: completed.strength, edgeAware: completed.edgeAware,
                                            points: points))
                })
                .accessibilityLabel("Brush canvas. Click or drag on the photo to paint the selected mask.")
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(size.width, max(0, point.x)), y: min(size.height, max(0, point.y)))
    }

    static func sourcePoints(_ points: [CGPoint], displayedSize: CGSize,
                             geometry: PhotoGeometry) -> [BrushPoint] {
        guard displayedSize.width > 0, displayedSize.height > 0 else { return [] }
        return points.map {
            geometry.sourcePoint(x: $0.x / displayedSize.width, y: $0.y / displayedSize.height)
        }
    }
}
