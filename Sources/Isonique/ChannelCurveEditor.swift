import SwiftUI
import IsoniqueCore

extension Workspace {
    func setChannelCurve(_ curve: ChannelCurve, for channel: CurveChannel, photoID: UUID) {
        guard !busy, !batchMode, !isViewingTrash, selected?.id == photoID,
              selected?.adjustments.curve(for: channel) != curve else { return }
        compareOriginal = false
        edit { $0.adjustments.setCurve(curve, for: channel) }
    }
}

struct ChannelCurveEditor: View {
    @EnvironmentObject private var model: Workspace
    let photo: Photo
    @State private var channel: CurveChannel = .red
    @State private var pointIndex = 0
    @State private var drag: CurveDrag?

    private struct CurveDrag {
        var curve: ChannelCurve
        let index: Int
        let start: CurvePoint
    }

    private var saved: ChannelCurve { photo.adjustments.curve(for: channel) }
    private var curve: ChannelCurve { drag?.curve ?? saved }
    private var index: Int { min(pointIndex, curve.points.count - 1) }
    private var isInteriorPoint: Bool { index > 0 && index < curve.points.count - 1 }
    private var tint: Color {
        switch channel {
        case .red: .red
        case .green: .green
        case .blue: .blue
        case .luminance: .primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Curve channel", selection: $channel) {
                ForEach(CurveChannel.allCases) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented)
            graph
            Picker("Point", selection: Binding(get: { index }, set: { pointIndex = $0 })) {
                ForEach(curve.points.indices, id: \.self) { point in
                    Text("\(curve.points[point].input) → \(curve.points[point].output)").tag(point)
                }
            }
            Stepper("Input \(curve.points[index].input)", value: inputBinding, in: 0...255)
                .disabled(!isInteriorPoint)
            Stepper("Output \(curve.points[index].output)", value: outputBinding, in: 0...255)
            HStack {
                Button("Add Point", action: insertMidpoint)
                    .disabled(curve.points.count >= ChannelCurve.pointLimit)
                Button("Remove Point") {
                    var edit = saved
                    edit.removePoint(at: index)
                    pointIndex = max(0, index - 1)
                    commit(edit)
                }.disabled(!isInteriorPoint)
                Spacer()
                Button("Reset Channel") {
                    pointIndex = 0
                    commit(.identity)
                }.disabled(saved == .identity)
            }
            Text("Drag points on the graph or use the input and output controls. Each curve uses values from 0 to 255.")
                .font(.caption2).foregroundStyle(.secondary)
        }.onChange(of: channel) { _, _ in
            pointIndex = 0
            drag = nil
        }
    }

    private var graph: some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Rectangle().fill(.black.opacity(0.35))
                Path { path in
                    for division in 1...3 {
                        let x = size.width * CGFloat(division) / 4
                        let y = size.height * CGFloat(division) / 4
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    path.move(to: CGPoint(x: 0, y: size.height))
                    path.addLine(to: CGPoint(x: size.width, y: 0))
                }.stroke(.secondary.opacity(0.45), lineWidth: 0.5)
                Path { path in
                    path.addLines(curve.points.map { position($0, in: size) })
                }.stroke(tint, lineWidth: 2)
                ForEach(curve.points.indices, id: \.self) { point in
                    Circle().fill(tint)
                        .overlay { Circle().strokeBorder(.white, lineWidth: point == index ? 2 : 0.5) }
                        .frame(width: 9, height: 9)
                        .position(position(curve.points[point], in: size))
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { updateDrag($0, in: size) }
                    .onEnded { value in
                        updateDrag(value, in: size)
                        if let drag { commit(drag.curve) }
                        drag = nil
                    })
        }.frame(height: 130).padding(5).accessibilityHidden(true)
    }

    private var inputBinding: Binding<Int> {
        Binding(get: { curve.points[index].input }, set: { movePoint(input: $0, output: curve.points[index].output) })
    }

    private var outputBinding: Binding<Int> {
        Binding(get: { curve.points[index].output }, set: { movePoint(input: curve.points[index].input, output: $0) })
    }

    private func movePoint(input: Int, output: Int) {
        var edit = saved
        edit.movePoint(at: index, input: input, output: output)
        commit(edit)
    }

    private func insertMidpoint() {
        var edit = saved
        let intervals = zip(edit.points, edit.points.dropFirst())
        guard let (left, right) = intervals.max(by: { $0.1.input - $0.0.input < $1.1.input - $1.0.input }) else { return }
        let input = (left.input + right.input) / 2
        let output = Int((edit.value(at: Double(input) / 255) * 255).rounded())
        guard let index = edit.insertPoint(input: input, output: output) else { return }
        pointIndex = index
        commit(edit)
    }

    private func updateDrag(_ value: DragGesture.Value, in size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        if drag == nil {
            var edit = saved
            let origin = value.startLocation
            let nearby = edit.points.indices.min {
                distance(from: origin, to: position(edit.points[$0], in: size)) <
                    distance(from: origin, to: position(edit.points[$1], in: size))
            }
            let index: Int
            if let nearby, distance(from: origin, to: position(edit.points[nearby], in: size)) <= 10 {
                index = nearby
            } else {
                let input = Int((origin.x / size.width * 255).rounded())
                let output = Int(((1 - origin.y / size.height) * 255).rounded())
                guard let inserted = edit.insertPoint(input: input, output: output) else { return }
                index = inserted
            }
            pointIndex = index
            drag = CurveDrag(curve: edit, index: index, start: edit.points[index])
        }
        guard var edit = drag else { return }
        let input = edit.start.input + Int((value.translation.width / size.width * 255).rounded())
        let output = edit.start.output - Int((value.translation.height / size.height * 255).rounded())
        edit.curve.movePoint(at: edit.index, input: input, output: output)
        drag = edit
    }

    private func position(_ point: CurvePoint, in size: CGSize) -> CGPoint {
        CGPoint(x: CGFloat(point.input) / 255 * size.width, y: (1 - CGFloat(point.output) / 255) * size.height)
    }

    private func distance(from a: CGPoint, to b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    private func commit(_ curve: ChannelCurve) { model.setChannelCurve(curve, for: channel, photoID: photo.id) }
}
