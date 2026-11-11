import SwiftUI
import IsoniqueCore

struct TargetedColorEditor: View {
    @EnvironmentObject private var model: Workspace
    let photo: Photo

    private var targets: [TargetedColorAdjustment] { photo.adjustments.targetedColors }
    private var selectedID: UUID? {
        if let selected = model.targetedColorSelection, targets.contains(where: { $0.id == selected }) {
            return selected
        }
        return targets.first?.id
    }
    private var selected: TargetedColorAdjustment? {
        selectedID.flatMap { id in targets.first(where: { $0.id == id }) }
    }

    var body: some View {
        DisclosureGroup("Targeted Color") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Menu("Add Range") {
                        ForEach(TargetedColorPreset.allCases) { preset in
                            Button(preset.rawValue) { add(preset.adjustment()) }
                        }
                    }.fixedSize()
                    Button {
                        model.startTargetedColorSampling(photoID: photo.id)
                    } label: {
                        Label("Sample", systemImage: "eyedropper")
                    }.disabled(model.busy || !model.canShowLoupe)
                }
                if targets.isEmpty {
                    Text("Add a reusable color range or sample one with the Viewer Loupe.")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    Picker("Range", selection: Binding(get: { selectedID }, set: { model.targetedColorSelection = $0 })) {
                        ForEach(targets) { target in Text(target.name).tag(Optional(target.id)) }
                    }
                    HStack {
                        Button("Duplicate", action: duplicate)
                        Button("Remove", action: remove)
                        Spacer()
                        Button("Remove All") { model.edit { $0.adjustments.targetedColors = [] } }
                    }.font(.caption)
                    colorAdjustment("Center", path: \.centerHue, range: 0...360, suffix: "°")
                    colorAdjustment("Core width", path: \.width, range: 0...180, suffix: "°")
                    colorAdjustment("Falloff", path: \.falloff, range: 0...180, suffix: "°")
                    colorAdjustment("Hue", path: \.hueShift, range: -180...180, suffix: "°")
                    colorAdjustment("Saturation", path: \.saturation, range: -1...1)
                    colorAdjustment("Luminance", path: \.luminance, range: -1...1)
                    Button("Reset Range") {
                        update { target in
                            target.hueShift = 0
                            target.saturation = 0
                            target.luminance = 0
                        }
                    }.disabled(selected?.isNeutral != false)
                }
                Text("Core width is fully affected; Falloff feathers to unchanged color. Overlapping ranges combine from the original hue.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(.top, 10)
        }
    }

    private func add(_ target: TargetedColorAdjustment) {
        var target = target
        let names = Set(targets.map(\.name))
        if names.contains(target.name) {
            var number = 2
            while names.contains("\(target.name) \(number)") { number += 1 }
            target.name += " \(number)"
        }
        model.edit { $0.adjustments.targetedColors.append(target) }
        if model.selected?.adjustments.targetedColors.contains(where: { $0.id == target.id }) == true {
            model.targetedColorSelection = target.id
        }
    }

    private func duplicate() {
        guard var copy = selected else { return }
        copy.id = UUID()
        copy.name += " Copy"
        add(copy)
    }

    private func remove() {
        guard let id = selectedID else { return }
        model.edit { $0.adjustments.targetedColors.removeAll { $0.id == id } }
        model.targetedColorSelection = model.selected?.adjustments.targetedColors.first?.id
    }

    private func update(_ change: @escaping (inout TargetedColorAdjustment) -> Void) {
        guard let id = selectedID else { return }
        model.edit { photo in
            guard let index = photo.adjustments.targetedColors.firstIndex(where: { $0.id == id }) else { return }
            change(&photo.adjustments.targetedColors[index])
        }
    }

    private func colorAdjustment(_ title: String, path: WritableKeyPath<TargetedColorAdjustment, Double>,
                                 range: ClosedRange<Double>, suffix: String = "") -> some View {
        let value = Binding<Double>(get: {
            selected?[keyPath: path] ?? 0
        }, set: { input in
            guard input.isFinite else { return }
            update { $0[keyPath: path] = min(range.upperBound, max(range.lowerBound, input)) }
        })
        return VStack(spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                TextField(title, value: value, format: .number.precision(.fractionLength(suffix.isEmpty ? 2 : 0)))
                    .textFieldStyle(.roundedBorder).frame(width: 62).multilineTextAlignment(.trailing)
                if !suffix.isEmpty { Text(suffix).foregroundStyle(.secondary) }
            }.font(.caption)
            Slider(value: value, in: range).accessibilityLabel(title)
        }
    }
}
