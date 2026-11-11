import SwiftUI
import IsoniqueCore

enum SpotPointKind: String, CaseIterable, Identifiable {
    case source = "Source"
    case destination = "Destination"
    var id: Self { self }
}

extension Workspace {
    var canSpotRemove: Bool {
        guard !busy, !batchMode, !isViewingTrash, let selected else { return false }
        return isOriginalAvailable(selected) == true
    }

    func chooseSpotRemoval(_ mode: SpotRemovalMode) {
        guard canSpotRemove else { return }
        spotMode = mode
        spotDraftSource = nil
        selectedSpotID = nil
        spotPlacement = .source
        chooseTool(.spot)
    }

    func beginNewSpot() {
        selectedSpotID = nil
        spotDraftSource = nil
        spotPlacement = .source
    }

    func selectSpot(_ id: UUID) {
        guard let spot = selected?.adjustments.spotRemovals.first(where: { $0.id == id }) else {
            beginNewSpot()
            return
        }
        selectedSpotID = id
        spotMode = spot.mode
        spotDraftSource = nil
        spotPlacement = .destination
    }

    func placeSpotPoint(_ point: BrushPoint, radius: Double, in photoID: UUID) {
        guard canSpotRemove, tool == .spot, selection == photoID else { return }
        if let selectedSpotID,
           selected?.adjustments.spotRemovals.contains(where: { $0.id == selectedSpotID }) == true {
            let placement = spotPlacement
            edit { photo in
                guard let index = photo.adjustments.spotRemovals.firstIndex(where: { $0.id == selectedSpotID }) else { return }
                if placement == .source { photo.adjustments.spotRemovals[index].source = point }
                else { photo.adjustments.spotRemovals[index].destination = point }
            }
            return
        }
        if spotPlacement == .source {
            spotDraftSource = point
            spotPlacement = .destination
            return
        }
        guard let source = spotDraftSource else {
            spotPlacement = .source
            return
        }
        let spot = SpotRemoval(mode: spotMode, source: source, destination: point,
                               radius: min(0.25, max(0.0025, radius)))
        edit { $0.adjustments.spotRemovals.append(spot) }
        selectedSpotID = spot.id
        spotDraftSource = nil
        spotPlacement = .destination
    }

    func setSelectedSpotMode(_ mode: SpotRemovalMode) {
        spotMode = mode
        guard let selectedSpotID else { return }
        edit { photo in
            guard let index = photo.adjustments.spotRemovals.firstIndex(where: { $0.id == selectedSpotID }),
                  photo.adjustments.spotRemovals[index].mode != mode else { return }
            photo.adjustments.spotRemovals[index].mode = mode
        }
    }

    func setSelectedSpotRadius(_ radius: Double) {
        guard let selectedSpotID else { return }
        let radius = min(0.25, max(0.0025, radius))
        edit { photo in
            guard let index = photo.adjustments.spotRemovals.firstIndex(where: { $0.id == selectedSpotID }),
                  photo.adjustments.spotRemovals[index].radius != radius else { return }
            photo.adjustments.spotRemovals[index].radius = radius
        }
    }

    func deleteSelectedSpot() {
        guard let selectedSpotID else { return }
        edit { $0.adjustments.spotRemovals.removeAll { $0.id == selectedSpotID } }
        beginNewSpot()
    }

    func clearSpots() {
        guard selected?.adjustments.spotRemovals.isEmpty == false else { return }
        edit { $0.adjustments.spotRemovals.removeAll() }
        beginNewSpot()
    }
}

struct SpotRemovalControls: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    @Binding var size: Double
    @State private var editingSize: Double?

    private var spots: [SpotRemoval] { photo.adjustments.spotRemovals }
    private var selectedSpot: SpotRemoval? {
        spots.first { $0.id == model.selectedSpotID }
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("Mode", selection: Binding(get: { model.spotMode }, set: model.setSelectedSpotMode)) {
                    ForEach(SpotRemovalMode.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 150)
                Picker("Spot", selection: Binding<UUID?>(get: { model.selectedSpotID }, set: { id in
                    if let id { model.selectSpot(id) } else { model.beginNewSpot() }
                })) {
                    Text("New Spot").tag(UUID?.none)
                    ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                        Text("Spot \(index + 1) · \(spot.mode.rawValue)").tag(Optional(spot.id))
                    }
                }.frame(maxWidth: 190)
                Picker("Point", selection: $model.spotPlacement) {
                    ForEach(SpotPointKind.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented).frame(width: 190)
                Button("New Spot", action: model.beginNewSpot)
                Button("Delete", action: model.deleteSelectedSpot).disabled(selectedSpot == nil)
                Button("Reset All", action: model.clearSpots).disabled(spots.isEmpty)
                Spacer()
                Button("Done") { model.chooseTool(.select) }
            }
            HStack(spacing: 12) {
                Text("Size").foregroundStyle(.secondary)
                Slider(value: Binding(get: {
                    editingSize ?? selectedSpot.map { $0.radius * 200 } ?? size
                }, set: { editingSize = $0 }), in: 1...50, step: 1) { editing in
                    if !editing, let value = editingSize {
                        size = value
                        model.setSelectedSpotRadius(value / 200)
                        editingSize = nil
                    }
                }.frame(maxWidth: 260).accessibilityLabel("Spot size")
                Text("\(Int((editingSize ?? selectedSpot.map { $0.radius * 200 } ?? size).rounded()))%")
                    .monospacedDigit().frame(width: 45, alignment: .trailing)
                Text(instruction).foregroundStyle(.secondary)
                Spacer()
            }.font(.caption)
        }.font(.caption)
    }

    private var instruction: String {
        if model.selectedSpotID != nil { return "Choose Source or Destination, then click the photo to move it." }
        if model.spotDraftSource == nil { return "Click a clean source area." }
        return "Now click the blemish destination."
    }
}

struct SpotRemovalCanvas: View {
    @EnvironmentObject var model: Workspace
    let image: ViewerImage
    let geometry: PhotoGeometry
    let photo: Photo
    let radius: Double

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            ZStack(alignment: .topLeading) {
                ClippingPreview(image: image).frame(width: size.width, height: size.height)
                ForEach(photo.adjustments.spotRemovals) { spot in
                    spotOverlay(spot, in: size, selected: spot.id == model.selectedSpotID)
                }
                if let source = model.spotDraftSource, let point = geometry.viewerPoint(source) {
                    marker(at: point, in: size, diameter: diameter(radius, in: size), color: .cyan, dashed: true)
                }
            }.frame(width: size.width, height: size.height).clipped().contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                    let point = CGPoint(x: min(size.width, max(0, gesture.location.x)),
                                        y: min(size.height, max(0, gesture.location.y)))
                    model.placeSpotPoint(geometry.sourcePoint(x: point.x / size.width, y: point.y / size.height),
                                         radius: radius, in: photo.id)
                })
                .accessibilityLabel("Spot removal canvas. Choose source or destination, then click the photo.")
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    @ViewBuilder private func spotOverlay(_ spot: SpotRemoval, in size: CGSize, selected: Bool) -> some View {
        let diameter = diameter(spot.radius, in: size)
        if let source = geometry.viewerPoint(spot.source), let destination = geometry.viewerPoint(spot.destination) {
            let sourcePoint = CGPoint(x: source.x * size.width, y: source.y * size.height)
            let destinationPoint = CGPoint(x: destination.x * size.width, y: destination.y * size.height)
            Path { path in path.move(to: sourcePoint); path.addLine(to: destinationPoint) }
                .stroke(selected ? Color.white.opacity(0.9) : Color.white.opacity(0.45), lineWidth: selected ? 2 : 1)
                .allowsHitTesting(false)
            marker(at: source, in: size, diameter: diameter, color: .cyan, dashed: true)
            marker(at: destination, in: size, diameter: diameter,
                   color: spot.mode == .repair ? .orange : .purple, dashed: false)
        } else if let source = geometry.viewerPoint(spot.source) {
            marker(at: source, in: size, diameter: diameter, color: .cyan, dashed: true)
        } else if let destination = geometry.viewerPoint(spot.destination) {
            marker(at: destination, in: size, diameter: diameter,
                   color: spot.mode == .repair ? .orange : .purple, dashed: false)
        }
    }

    private func marker(at point: CGPoint, in size: CGSize, diameter: CGFloat,
                        color: Color, dashed: Bool) -> some View {
        Circle().stroke(color, style: StrokeStyle(lineWidth: 2, dash: dashed ? [5, 4] : []))
            .background(Circle().fill(.black.opacity(0.12)))
            .frame(width: diameter, height: diameter)
            .position(x: point.x * size.width, y: point.y * size.height)
            .allowsHitTesting(false)
    }

    private func diameter(_ radius: Double, in size: CGSize) -> CGFloat {
        max(4, 2 * radius * min(size.width, size.height))
    }
}
