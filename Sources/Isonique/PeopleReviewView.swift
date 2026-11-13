import IsoniqueCore
import SwiftUI

struct PeopleReviewView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    let review: PeopleReview
    @State private var people: PhotoPeople
    @State private var image: CGImage?
    @State private var previewError: String?
    @State private var scanError: String?
    @State private var scanID: UUID?
    @State private var faceID: UUID?
    @State private var nameDrafts: [UUID: String] = [:]
    @State private var placement: Placement?
    @State private var drawing: FaceRegion?

    private enum Placement: Equatable { case add, redraw(UUID) }

    init(review: PeopleReview) {
        self.review = review
        let people = review.photo.people ?? PhotoPeople()
        _people = State(initialValue: people)
        _faceID = State(initialValue: people.faces.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Review Faces").font(.title2.bold())
            Text(review.photo.displayName).lineLimit(1).foregroundStyle(.secondary)
            HStack(spacing: 16) {
                preview.frame(width: 490, height: 360)
                faceList.frame(width: 252, height: 360)
            }
            HStack {
                Button("Detect Faces on This Mac", systemImage: "face.dashed") {
                    scanID = UUID()
                }.disabled(image == nil || scanID != nil || placement != nil)
                if scanID != nil {
                    ProgressView().controlSize(.small).accessibilityLabel("Detecting faces")
                    Button("Cancel Detection") { scanID = nil }
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save People") {
                    if model.applyPeopleReview(review, people: people) { dismiss() }
                    else { scanError = model.error }
                }.keyboardShortcut(.defaultAction).disabled(scanID != nil || placement != nil)
            }
            if let scanError { Text(scanError).foregroundStyle(.red) }
            Text("Face detection runs on this Mac. Boxes, names and corrections are kept in the catalogue.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .task { await loadPreview() }
        .task(id: scanID) {
            guard let id = scanID, let image else { return }
            do {
                let regions = try await FaceDetection.regions(in: image)
                guard !Task.isCancelled, scanID == id else { return }
                people.incorporateDetections(regions)
                if faceID == nil { faceID = people.faces.first?.id }
                scanError = nil
                scanID = nil
            } catch {
                guard !Task.isCancelled, scanID == id else { return }
                scanError = error.localizedDescription
                scanID = nil
            }
        }
    }

    @ViewBuilder private var preview: some View {
        if let image {
            GeometryReader { proxy in
                let scale = min(proxy.size.width / CGFloat(image.width), proxy.size.height / CGFloat(image.height))
                let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1, orientation: .up).resizable()
                        .frame(width: size.width, height: size.height)
                        .accessibilityLabel("Oriented original")
                    ForEach(Array(people.faces.enumerated()), id: \.element.id) { index, face in
                        let rect = face.region.rect
                        Button {
                            faceID = face.id
                        } label: {
                            ZStack(alignment: .topLeading) {
                                Rectangle().strokeBorder(faceID == face.id ? Color.yellow : Color.white, lineWidth: 2)
                                Text("\(index + 1)").font(.caption2.bold())
                                    .padding(3).background(.black).foregroundStyle(.white)
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(Text(face.name ?? String(localized: "Face \(index + 1)")))
                            .frame(width: rect.width * size.width, height: rect.height * size.height)
                            .offset(x: rect.minX * size.width, y: rect.minY * size.height)
                    }
                    if placement != nil {
                        Color.clear.contentShape(Rectangle())
                            .gesture(DragGesture(minimumDistance: 4)
                                .onChanged { drawing = Self.region(from: $0, size: size) }
                                .onEnded { finishPlacement(Self.region(from: $0, size: size)) })
                    }
                    if let rect = drawing?.rect {
                        Rectangle().strokeBorder(.yellow, style: StrokeStyle(lineWidth: 2, dash: [4]))
                            .frame(width: rect.width * size.width, height: rect.height * size.height)
                            .offset(x: rect.minX * size.width, y: rect.minY * size.height)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: size.width, height: size.height).clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }.background(.black)
        } else if let previewError {
            ContentUnavailableView("Original Unavailable", systemImage: "photo.badge.exclamationmark",
                                   description: Text(previewError))
        } else {
            ProgressView("Loading original…")
        }
    }

    private var faceList: some View {
        VStack(alignment: .leading, spacing: 10) {
            if people.faces.isEmpty {
                Text(people.scanned ? "No faces to review" : "No faces catalogued").foregroundStyle(.secondary)
            } else {
                List(selection: $faceID) {
                    ForEach(Array(people.faces.enumerated()), id: \.element.id) { index, face in
                        Label(face.name ?? String(localized: "Unnamed Face \(index + 1)"), systemImage: "person.crop.rectangle")
                            .lineLimit(1).tag(face.id)
                    }
                }.accessibilityLabel("Faces in this photo")
            }
            if let index = people.faces.firstIndex(where: { $0.id == faceID }) {
                let id = people.faces[index].id
                TextField("Person’s name", text: Binding(
                    get: { nameDrafts[id] ?? people.faces.first(where: { $0.id == id })?.name ?? "" },
                    set: { assign($0, to: id) }
                ))
                Menu("Use Existing Name") {
                    ForEach(model.peopleGroups) { group in
                        Button(group.name) { assign(group.name, to: id) }
                    }
                }.disabled(model.peopleGroups.isEmpty)
                HStack {
                    Button("Redraw Box") { placement = .redraw(id) }.disabled(image == nil)
                    Button("Remove Face", role: .destructive) {
                        people.removeFace(id)
                        nameDrafts.removeValue(forKey: id)
                        faceID = people.faces.first?.id
                    }
                }
            }
            Spacer(minLength: 0)
            if placement != nil {
                Text("Drag a box around the face.").font(.caption)
                Button("Cancel Box Placement") { finishPlacement(nil) }
            } else {
                Button("Add Face Box", systemImage: "plus") { placement = .add }.disabled(image == nil)
            }
        }
        .disabled(scanID != nil)
    }

    private func assign(_ name: String, to id: UUID) {
        guard let index = people.faces.firstIndex(where: { $0.id == id }) else { return }
        nameDrafts[id] = name
        people.faces[index].assignName(name)
        if let original = review.photo.people?.faces.first(where: { $0.id == id }),
           let oldName = original.name, let newName = people.faces[index].name,
           PhotoFace.personKey(oldName) == PhotoFace.personKey(newName) {
            people.faces[index].setRepresentative(chosenAt: original.representativeChosenAt)
        }
    }

    private func loadPreview() async {
        guard let repository = model.repository, repository.root == review.root else {
            previewError = String(localized: "The library changed.")
            return
        }
        let photo = review.photo
        let load = Task.detached(priority: .userInitiated) { try repository.verifiedFaceSource(for: photo) }
        do {
            let preview = try await withTaskCancellationHandler { try await load.value } onCancel: { load.cancel() }
            if !Task.isCancelled { image = preview }
        } catch {
            if !Task.isCancelled { previewError = error.localizedDescription }
        }
    }

    private static func region(from drag: DragGesture.Value, size: CGSize) -> FaceRegion? {
        guard size.width > 0, size.height > 0 else { return nil }
        let origin = CGPoint(x: min(drag.startLocation.x, drag.location.x) / size.width,
                             y: min(drag.startLocation.y, drag.location.y) / size.height)
        return FaceRegion(imageRect: CGRect(origin: origin, size: CGSize(
            width: abs(drag.translation.width) / size.width, height: abs(drag.translation.height) / size.height
        )))
    }

    private func finishPlacement(_ region: FaceRegion?) {
        defer { placement = nil; drawing = nil }
        guard let placement, let region else { return }
        switch placement {
        case .add:
            let face = PhotoFace(region: region)
            people.faces.append(face)
            faceID = face.id
        case .redraw(let id):
            people.moveFace(id, to: region)
            faceID = id
        }
    }
}
