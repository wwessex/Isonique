import SwiftUI
import AppKit
import IsoniqueCore

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
        edit { $0.adjustments.localBrushes.removeAll { $0.adjustment == adjustment } }
    }
}

struct BrushControls: View {
    @Binding var adjustment: LocalBrushAdjustment
    @Binding var erasing: Bool
    @Binding var size: Double
    @Binding var softness: Double
    @Binding var strength: Double
    let hasMask: Bool
    let reset: () -> Void
    let done: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Brush adjustment", selection: $adjustment) {
                    ForEach(LocalBrushAdjustment.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 150)
                Toggle("Erase", isOn: $erasing).toggleStyle(.button).help("Erase from the selected mask")
                Spacer()
                Button("Reset Mask", action: reset).disabled(!hasMask)
                Button("Done", action: done)
            }
            HStack(spacing: 10) {
                slider("Size", value: $size, range: 1...50)
                slider("Softness", value: $softness, range: 0...100)
                slider("Strength", value: $strength, range: 1...100)
            }
        }.font(.caption)
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
    let commit: (LocalBrushStroke) -> Void
    @State private var hover: CGPoint?
    @State private var draft: Draft?

    private struct Draft {
        let adjustment: LocalBrushAdjustment
        let erasing: Bool
        let radius: Double
        let softness: Double
        let strength: Double
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
                if let draft, let first = draft.points.first {
                    let color: Color = draft.erasing ? .white : (draft.adjustment == .dodge ? .yellow : .blue)
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
                                      softness: softness, strength: strength, points: [clamp(drag.startLocation, to: size)])
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
                    let points = completed.points.map {
                        geometry.sourcePoint(x: $0.x / size.width, y: $0.y / size.height)
                    }
                    commit(LocalBrushStroke(adjustment: completed.adjustment, erasing: completed.erasing,
                                            radius: completed.radius, softness: completed.softness,
                                            strength: completed.strength, points: points))
                })
                .accessibilityLabel("Brush canvas. Click or drag on the photo to paint the selected mask.")
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func clamp(_ point: CGPoint, to size: CGSize) -> CGPoint {
        CGPoint(x: min(size.width, max(0, point.x)), y: min(size.height, max(0, point.y)))
    }
}
