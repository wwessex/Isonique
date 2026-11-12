import SwiftUI
import IsoniqueCore

extension Workspace {
    var canCorrectRedEye: Bool {
        guard !busy, !batchMode, !isViewingTrash, !quickPreview, let selected else { return false }
        return isOriginalAvailable(selected) == true
    }

    func chooseRedEyeCorrection() {
        guard canCorrectRedEye else { return }
        selectedRedEyeID = nil
        chooseTool(.redEye)
    }

    func beginNewRedEye() {
        selectedRedEyeID = nil
    }

    func selectRedEye(_ id: UUID) {
        selectedRedEyeID = selected?.adjustments.redEyeCorrections.contains { $0.id == id } == true ? id : nil
    }

    func placeRedEye(_ point: BrushPoint, radius: Double, darkness: Double, in photoID: UUID) {
        guard canCorrectRedEye, tool == .redEye, selection == photoID else { return }
        if let selectedRedEyeID,
           selected?.adjustments.redEyeCorrections.contains(where: { $0.id == selectedRedEyeID }) == true {
            edit { photo in
                guard let index = photo.adjustments.redEyeCorrections.firstIndex(where: { $0.id == selectedRedEyeID }),
                      photo.adjustments.redEyeCorrections[index].center != point else { return }
                photo.adjustments.redEyeCorrections[index].center = point
            }
            return
        }
        let correction = RedEyeCorrection(center: point,
            radius: min(0.25, max(0.0025, radius)), darkness: min(1, max(0, darkness)))
        edit { $0.adjustments.redEyeCorrections.append(correction) }
        selectedRedEyeID = correction.id
    }

    func setSelectedRedEyeRadius(_ radius: Double) {
        guard let selectedRedEyeID else { return }
        let radius = min(0.25, max(0.0025, radius))
        edit { photo in
            guard let index = photo.adjustments.redEyeCorrections.firstIndex(where: { $0.id == selectedRedEyeID }),
                  photo.adjustments.redEyeCorrections[index].radius != radius else { return }
            photo.adjustments.redEyeCorrections[index].radius = radius
        }
    }

    func setSelectedRedEyeDarkness(_ darkness: Double) {
        guard let selectedRedEyeID else { return }
        let darkness = min(1, max(0, darkness))
        edit { photo in
            guard let index = photo.adjustments.redEyeCorrections.firstIndex(where: { $0.id == selectedRedEyeID }),
                  photo.adjustments.redEyeCorrections[index].darkness != darkness else { return }
            photo.adjustments.redEyeCorrections[index].darkness = darkness
        }
    }

    func deleteSelectedRedEye() {
        guard let selectedRedEyeID else { return }
        edit { $0.adjustments.redEyeCorrections.removeAll { $0.id == selectedRedEyeID } }
        beginNewRedEye()
    }

    func clearRedEyes() {
        guard selected?.adjustments.redEyeCorrections.isEmpty == false else { return }
        edit { $0.adjustments.redEyeCorrections.removeAll() }
        beginNewRedEye()
    }
}

struct RedEyeControls: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    @Binding var size: Double
    @Binding var darkness: Double
    @State private var editingSize: Double?
    @State private var editingDarkness: Double?

    private var corrections: [RedEyeCorrection] { photo.adjustments.redEyeCorrections }
    private var selected: RedEyeCorrection? { corrections.first { $0.id == model.selectedRedEyeID } }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Picker("Eye", selection: Binding<UUID?>(get: { model.selectedRedEyeID }, set: { id in
                    if let id { model.selectRedEye(id) } else { model.beginNewRedEye() }
                })) {
                    Text("New Eye").tag(UUID?.none)
                    ForEach(Array(corrections.enumerated()), id: \.element.id) { index, correction in
                        Text("Eye \(index + 1)").tag(Optional(correction.id))
                    }
                }.frame(maxWidth: 180)
                Button("New Eye", action: model.beginNewRedEye)
                Button("Delete", action: model.deleteSelectedRedEye).disabled(selected == nil)
                Button("Reset All", action: model.clearRedEyes).disabled(corrections.isEmpty)
                Text(selected == nil ? "Click the centre of a red pupil." : "Click the photo to move the selected pupil.")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { model.chooseTool(.select) }
            }
            HStack(spacing: 12) {
                Text("Pupil size").foregroundStyle(.secondary)
                Slider(value: Binding(get: {
                    editingSize ?? selected.map { $0.radius * 200 } ?? size
                }, set: { editingSize = $0 }), in: 1...50, step: 1) { editing in
                    if !editing, let value = editingSize {
                        size = value
                        model.setSelectedRedEyeRadius(value / 200)
                        editingSize = nil
                    }
                }.frame(maxWidth: 220).accessibilityLabel("Red-eye pupil size")
                Text("\(Int((editingSize ?? selected.map { $0.radius * 200 } ?? size).rounded()))%")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                Text("Darkness").foregroundStyle(.secondary)
                Slider(value: Binding(get: {
                    editingDarkness ?? selected.map { $0.darkness * 100 } ?? darkness
                }, set: { editingDarkness = $0 }), in: 0...100, step: 1) { editing in
                    if !editing, let value = editingDarkness {
                        darkness = value
                        model.setSelectedRedEyeDarkness(value / 100)
                        editingDarkness = nil
                    }
                }.frame(maxWidth: 220).accessibilityLabel("Red-eye darkness")
                Text("\(Int((editingDarkness ?? selected.map { $0.darkness * 100 } ?? darkness).rounded()))%")
                    .monospacedDigit().frame(width: 42, alignment: .trailing)
            }.font(.caption)
        }.font(.caption)
    }
}

struct RedEyeCanvas: View {
    @EnvironmentObject var model: Workspace
    let image: ViewerImage
    let geometry: PhotoGeometry
    let photo: Photo
    let radius: Double
    let darkness: Double

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / image.size.width, proxy.size.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            ZStack(alignment: .topLeading) {
                ClippingPreview(image: image).frame(width: size.width, height: size.height)
                ForEach(photo.adjustments.redEyeCorrections) { correction in
                    if let point = geometry.viewerPoint(correction.center) {
                        Circle()
                            .stroke(correction.id == model.selectedRedEyeID ? Color.yellow : Color.white.opacity(0.7),
                                    style: StrokeStyle(lineWidth: correction.id == model.selectedRedEyeID ? 2 : 1,
                                                       dash: [5, 3]))
                            .background(Circle().fill(.black.opacity(0.08)))
                            .frame(width: diameter(correction.radius, in: size),
                                   height: diameter(correction.radius, in: size))
                            .position(x: point.x * size.width, y: point.y * size.height)
                            .allowsHitTesting(false)
                    }
                }
            }.frame(width: size.width, height: size.height).clipped().contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { gesture in
                    let point = CGPoint(x: min(size.width, max(0, gesture.location.x)),
                                        y: min(size.height, max(0, gesture.location.y)))
                    model.placeRedEye(geometry.sourcePoint(x: point.x / size.width, y: point.y / size.height),
                                      radius: radius, darkness: darkness, in: photo.id)
                })
                .accessibilityLabel("Red-eye correction canvas. Click the centre of a red pupil.")
                .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }

    private func diameter(_ radius: Double, in size: CGSize) -> CGFloat {
        max(4, 2 * radius * min(size.width, size.height))
    }
}
