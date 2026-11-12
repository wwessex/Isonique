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
        case .tint: return .red
        case .skinSmoothing: return .brown
        case .polarize: return .blue
        case .haloReduction: return .green
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
        brushInstanceID = selected?.adjustments.localBrushInstances(for: adjustment).first?.id
        chooseTool(.brush)
    }

    func applyBrushStroke(_ stroke: LocalBrushStroke, to id: UUID) {
        guard tool == .brush, !batchMode, selection == id, stroke.isValid else { return }
        let targetID = brushInstanceID
            ?? selected?.adjustments.localBrushInstances(for: stroke.adjustment).first?.id
            ?? UUID()
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            if let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }) {
                guard photo.adjustments.localBrushInstances[index].adjustment == stroke.adjustment else { return }
                if stroke.erasing && !photo.adjustments.localBrushInstances[index].strokes.contains(where: {
                    !$0.erasing
                }) { return }
                photo.adjustments.localBrushInstances[index].strokes.append(stroke)
            } else {
                guard !stroke.erasing else { return }
                photo.adjustments.localBrushInstances.append(LocalBrushInstance(id: targetID,
                    name: nextBrushInstanceName(stroke.adjustment, in: photo.adjustments),
                    adjustment: stroke.adjustment, strokes: [stroke]))
            }
        }
        brushInstanceID = targetID
    }

    func clearBrushMask(_ adjustment: LocalBrushAdjustment) {
        guard !batchMode, let targetID = activeBrushInstanceID(for: adjustment) else { return }
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }) else {
                return
            }
            photo.adjustments.localBrushInstances[index].strokes = []
            photo.adjustments.localBrushInstances[index].maskSettings = LocalBrushMaskSettings()
        }
    }

    func setBrushMaskOpacity(_ opacity: Double, for adjustment: LocalBrushAdjustment) {
        guard !batchMode, let targetID = activeBrushInstanceID(for: adjustment),
              selected?.adjustments.localBrushInstance(id: targetID)?.strokes.contains(where: { !$0.erasing }) == true
        else { return }
        let value = opacity.isFinite ? min(1, max(0, opacity)) : 1
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }),
                  photo.adjustments.localBrushInstances[index].maskSettings.opacity != value else { return }
            photo.adjustments.localBrushInstances[index].maskSettings.opacity = value
        }
    }

    func invertBrushMask(_ adjustment: LocalBrushAdjustment) {
        guard !batchMode, let targetID = activeBrushInstanceID(for: adjustment),
              selected?.adjustments.localBrushInstance(id: targetID)?.strokes.contains(where: { !$0.erasing }) == true
        else { return }
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }) else {
                return
            }
            photo.adjustments.localBrushInstances[index].maskSettings.inverted.toggle()
        }
    }

    func setLocalTintSettings(_ settings: LocalTintSettings) {
        guard !batchMode, let targetID = activeBrushInstanceID(for: .tint) else { return }
        let hue = settings.hue.isFinite
            ? (settings.hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) : 30
        let saturation = settings.saturation.isFinite ? min(1, max(0, settings.saturation)) : 0
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }) else {
                return
            }
            let value = LocalTintSettings(hue: hue, saturation: saturation)
            guard photo.adjustments.localBrushInstances[index].tintSettings != value else { return }
            photo.adjustments.localBrushInstances[index].tintSettings = value
        }
    }

    func setLocalSkinSmoothingSettings(_ settings: LocalSkinSmoothingSettings) {
        guard !batchMode, let targetID = activeBrushInstanceID(for: .skinSmoothing) else { return }
        let amount = settings.amount.isFinite ? min(1, max(0, settings.amount)) : 0
        let detail = settings.detailPreservation.isFinite
            ? min(1, max(0, settings.detailPreservation)) : 0.5
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }) else {
                return
            }
            let value = LocalSkinSmoothingSettings(amount: amount, detailPreservation: detail)
            guard photo.adjustments.localBrushInstances[index].skinSmoothingSettings != value else { return }
            photo.adjustments.localBrushInstances[index].skinSmoothingSettings = value
        }
    }

    func setLocalPolarizeSettings(_ settings: LocalPolarizeSettings) {
        guard !batchMode, let targetID = activeBrushInstanceID(for: .polarize) else { return }
        let value = LocalPolarizeSettings(intensity: settings.intensity.isFinite
            ? min(1, max(0, settings.intensity)) : 0)
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }),
                  photo.adjustments.localBrushInstances[index].polarizeSettings != value else { return }
            photo.adjustments.localBrushInstances[index].polarizeSettings = value
        }
    }

    func setLocalHaloReductionSettings(_ settings: LocalHaloReductionSettings) {
        guard !batchMode, let targetID = activeBrushInstanceID(for: .haloReduction) else { return }
        let amount = settings.amount.isFinite ? min(1, max(0, settings.amount)) : 0
        let radius = settings.radius.isFinite ? min(0.08, max(0.0025, settings.radius)) : 0.015
        let value = LocalHaloReductionSettings(amount: amount, radius: radius)
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == targetID }),
                  photo.adjustments.localBrushInstances[index].haloReductionSettings != value else { return }
            photo.adjustments.localBrushInstances[index].haloReductionSettings = value
        }
    }

    func selectBrushInstance(for adjustment: LocalBrushAdjustment) {
        brushInstanceID = selected?.adjustments.localBrushInstances(for: adjustment).first?.id
    }

    func createBrushInstance(_ adjustment: LocalBrushAdjustment) {
        guard canBrush else { return }
        let id = UUID()
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            photo.adjustments.localBrushInstances.append(LocalBrushInstance(id: id,
                name: nextBrushInstanceName(adjustment, in: photo.adjustments), adjustment: adjustment))
        }
        brushInstanceID = id
    }

    func renameBrushInstance(_ id: UUID, to name: String) {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !batchMode, !value.isEmpty else { return }
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == id }),
                  photo.adjustments.localBrushInstances[index].name != value else { return }
            photo.adjustments.localBrushInstances[index].name = value
        }
    }

    func setBrushInstanceEnabled(_ id: UUID, enabled: Bool) {
        guard !batchMode else { return }
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == id }),
                  photo.adjustments.localBrushInstances[index].enabled != enabled else { return }
            photo.adjustments.localBrushInstances[index].enabled = enabled
        }
    }

    func duplicateBrushInstance(_ id: UUID) {
        guard !batchMode, let source = selected?.adjustments.localBrushInstance(id: id) else { return }
        let copyID = UUID()
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == id }) else {
                return
            }
            var copy = source
            copy.id = copyID
            copy.name = source.displayName + " Copy"
            photo.adjustments.localBrushInstances.insert(copy, at: index + 1)
        }
        brushInstanceID = copyID
    }

    func moveBrushInstance(_ id: UUID, by offset: Int) {
        guard !batchMode, offset != 0 else { return }
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            guard let index = photo.adjustments.localBrushInstances.firstIndex(where: { $0.id == id }) else {
                return
            }
            let adjustment = photo.adjustments.localBrushInstances[index].adjustment
            let siblings = photo.adjustments.localBrushInstances.indices.filter {
                photo.adjustments.localBrushInstances[$0].adjustment == adjustment
            }
            guard let position = siblings.firstIndex(of: index) else { return }
            let destination = position + offset
            guard siblings.indices.contains(destination) else { return }
            photo.adjustments.localBrushInstances.swapAt(index, siblings[destination])
        }
    }

    func deleteBrushInstance(_ id: UUID) {
        guard !batchMode, let instance = selected?.adjustments.localBrushInstance(id: id) else { return }
        let remaining = selected?.adjustments.localBrushInstances(for: instance.adjustment).filter { $0.id != id } ?? []
        edit { photo in
            photo.adjustments.migrateLocalBrushInstances()
            photo.adjustments.localBrushInstances.removeAll { $0.id == id }
        }
        brushInstanceID = remaining.first?.id
    }

    private func activeBrushInstanceID(for adjustment: LocalBrushAdjustment) -> UUID? {
        if let brushInstanceID,
           selected?.adjustments.localBrushInstance(id: brushInstanceID)?.adjustment == adjustment {
            return brushInstanceID
        }
        return selected?.adjustments.localBrushInstances(for: adjustment).first?.id
    }

    private func nextBrushInstanceName(_ adjustment: LocalBrushAdjustment, in adjustments: Adjustments) -> String {
        let count = adjustments.localBrushInstances(for: adjustment).count
        return count == 0 ? adjustment.rawValue : "\(adjustment.rawValue) \(count + 1)"
    }
}

struct BrushControls: View {
    @Binding var adjustment: LocalBrushAdjustment
    @Binding var instanceID: UUID?
    @Binding var erasing: Bool
    @Binding var size: Double
    @Binding var softness: Double
    @Binding var strength: Double
    @Binding var edgeAware: Bool
    @Binding var showMask: Bool
    let instances: [LocalBrushInstance]
    let hasMask: Bool
    let maskOpacity: Double
    let maskInverted: Bool
    let tintSettings: LocalTintSettings
    let skinSmoothingSettings: LocalSkinSmoothingSettings
    let polarizeSettings: LocalPolarizeSettings
    let haloReductionSettings: LocalHaloReductionSettings
    let setOpacity: (Double) -> Void
    let setTintSettings: (LocalTintSettings) -> Void
    let setSkinSmoothingSettings: (LocalSkinSmoothingSettings) -> Void
    let setPolarizeSettings: (LocalPolarizeSettings) -> Void
    let setHaloReductionSettings: (LocalHaloReductionSettings) -> Void
    let createInstance: () -> Void
    let renameInstance: (UUID, String) -> Void
    let setInstanceEnabled: (UUID, Bool) -> Void
    let duplicateInstance: (UUID) -> Void
    let moveInstance: (UUID, Int) -> Void
    let deleteInstance: (UUID) -> Void
    let invert: () -> Void
    let reset: () -> Void
    let done: () -> Void
    @State private var opacity = 100.0
    @State private var editingOpacity = false
    @State private var tintHue = 30.0
    @State private var tintSaturation = 35.0
    @State private var smoothingAmount = 50.0
    @State private var detailPreservation = 50.0
    @State private var polarizeIntensity = 50.0
    @State private var haloReductionAmount = 50.0
    @State private var haloReductionRadius = 1.5
    @State private var instanceName = ""

    private var selectedInstance: LocalBrushInstance? {
        instanceID.flatMap { id in instances.first { $0.id == id } }
    }

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
            HStack(spacing: 8) {
                Picker("Instance", selection: $instanceID) {
                    if instances.isEmpty { Text("New mask").tag(nil as UUID?) }
                    ForEach(instances) { instance in
                        Text(instance.enabled ? instance.displayName : "\(instance.displayName) (Off)")
                            .tag(Optional(instance.id))
                    }
                }.pickerStyle(.menu).frame(width: 190)
                Button(action: createInstance) { Label("New Instance", systemImage: "plus") }
                    .help("Create an empty \(adjustment.rawValue) instance")
                TextField("Instance name", text: $instanceName)
                    .textFieldStyle(.roundedBorder).frame(minWidth: 130, maxWidth: 220)
                    .onSubmit {
                        if let id = selectedInstance?.id { renameInstance(id, instanceName) }
                    }
                    .disabled(selectedInstance == nil)
                Button("Rename") {
                    if let id = selectedInstance?.id { renameInstance(id, instanceName) }
                }.disabled(selectedInstance == nil || instanceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Toggle("Enabled", isOn: Binding(get: { selectedInstance?.enabled ?? false }, set: { value in
                    if let id = selectedInstance?.id { setInstanceEnabled(id, value) }
                })).disabled(selectedInstance == nil)
                Button(action: { if let id = selectedInstance?.id { duplicateInstance(id) } }) {
                    Image(systemName: "plus.square.on.square")
                }.help("Duplicate instance").disabled(selectedInstance == nil)
                Button(action: { if let id = selectedInstance?.id { moveInstance(id, -1) } }) {
                    Image(systemName: "arrow.up")
                }.help("Move instance earlier").disabled(!canMove(-1))
                Button(action: { if let id = selectedInstance?.id { moveInstance(id, 1) } }) {
                    Image(systemName: "arrow.down")
                }.help("Move instance later").disabled(!canMove(1))
                Button(role: .destructive, action: {
                    if let id = selectedInstance?.id { deleteInstance(id) }
                }) { Image(systemName: "trash") }
                    .help("Delete instance").disabled(selectedInstance == nil)
                Spacer()
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
            if adjustment == .tint {
                HStack(spacing: 10) {
                    committedSlider("Tint Hue", value: $tintHue, range: 0...359, suffix: "°") {
                        setTintSettings(LocalTintSettings(hue: tintHue, saturation: tintSaturation / 100))
                    }
                    committedSlider("Tint Saturation", value: $tintSaturation, range: 0...100) {
                        setTintSettings(LocalTintSettings(hue: tintHue, saturation: tintSaturation / 100))
                    }
                }
            } else if adjustment == .skinSmoothing {
                HStack(spacing: 10) {
                    committedSlider("Smoothing", value: $smoothingAmount, range: 0...100) {
                        setSkinSmoothingSettings(LocalSkinSmoothingSettings(
                            amount: smoothingAmount / 100, detailPreservation: detailPreservation / 100))
                    }
                    committedSlider("Detail Preservation", value: $detailPreservation, range: 0...100) {
                        setSkinSmoothingSettings(LocalSkinSmoothingSettings(
                            amount: smoothingAmount / 100, detailPreservation: detailPreservation / 100))
                    }
                }
            } else if adjustment == .polarize {
                HStack(spacing: 10) {
                    committedSlider("Polarize Intensity", value: $polarizeIntensity, range: 0...100) {
                        setPolarizeSettings(LocalPolarizeSettings(intensity: polarizeIntensity / 100))
                    }
                }
            } else if adjustment == .haloReduction {
                HStack(spacing: 10) {
                    committedSlider("Halo Reduction", value: $haloReductionAmount, range: 0...100) {
                        setHaloReductionSettings(LocalHaloReductionSettings(
                            amount: haloReductionAmount / 100, radius: haloReductionRadius / 100))
                    }
                    committedSlider("Halo Radius", value: $haloReductionRadius, range: 0.25...8) {
                        setHaloReductionSettings(LocalHaloReductionSettings(
                            amount: haloReductionAmount / 100, radius: haloReductionRadius / 100))
                    }
                }
            }
        }.font(.caption)
            .onAppear { syncSettings() }
            .onChange(of: maskOpacity) { _, value in
                if !editingOpacity { opacity = value * 100 }
            }
            .onChange(of: tintSettings) { _, _ in syncSettings() }
            .onChange(of: skinSmoothingSettings) { _, _ in syncSettings() }
            .onChange(of: polarizeSettings) { _, _ in syncSettings() }
            .onChange(of: haloReductionSettings) { _, _ in syncSettings() }
            .onChange(of: instanceID) { _, _ in syncSettings() }
            .onChange(of: instances) { _, _ in syncSettings() }
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

    private func committedSlider(_ name: String, value: Binding<Double>, range: ClosedRange<Double>,
                                 suffix: String = "%", commit: @escaping () -> Void) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(name)
                Spacer(minLength: 2)
                Text(value.wrappedValue, format: .number.precision(.fractionLength(0))) + Text(suffix)
            }.monospacedDigit().foregroundStyle(.secondary)
            Slider(value: value, in: range, step: 1) { editing in
                if !editing { commit() }
            }.accessibilityLabel(name)
        }
    }

    private func syncSettings() {
        opacity = maskOpacity * 100
        tintHue = tintSettings.hue
        tintSaturation = tintSettings.saturation * 100
        smoothingAmount = skinSmoothingSettings.amount * 100
        detailPreservation = skinSmoothingSettings.detailPreservation * 100
        polarizeIntensity = polarizeSettings.intensity * 100
        haloReductionAmount = haloReductionSettings.amount * 100
        haloReductionRadius = haloReductionSettings.radius * 100
        instanceName = selectedInstance?.displayName ?? ""
    }

    private func canMove(_ offset: Int) -> Bool {
        guard let id = selectedInstance?.id,
              let index = instances.firstIndex(where: { $0.id == id }) else { return false }
        return instances.indices.contains(index + offset)
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
