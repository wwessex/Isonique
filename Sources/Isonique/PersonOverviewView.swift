import IsoniqueCore
import SwiftUI

struct PersonOverviewView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    let request: PersonOverviewRequest
    @State private var selection: PersonOverview.Face.ID?
    @State private var failure: String?

    var body: some View {
        let overview = PersonOverview(key: request.key, library: model.library)
        let person = model.peopleGroups.first { $0.id == request.key }
        let chosenID = overview.chosenFace?.id
        let displayedFace = overview.faces.first { $0.id == selection } ?? overview.portrait
        VStack(alignment: .leading, spacing: 14) {
            Text(person?.name ?? String(localized: "Person Overview")).font(.title2.bold())
            if let displayedFace {
                HStack(alignment: .top, spacing: 18) {
                    portrait(displayedFace, chosen: chosenID == displayedFace.id)
                        .frame(width: 250)
                    List {
                        Section("Photos by Project") {
                            ForEach(overview.projectCounts) { project in
                                LabeledContent(project.name, value: project.count.formatted())
                            }
                        }
                        Section("Choose a Representative Face") {
                            ForEach(overview.faces) { face in
                                Button {
                                    selection = face.id
                                    failure = nil
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text(face.photo.displayName).lineLimit(1)
                                            Text("Face \(face.number)").font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if face.id == chosenID {
                                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                                                .accessibilityLabel("Representative face")
                                        }
                                        if face.id == displayedFace.id {
                                            Image(systemName: "checkmark").accessibilityLabel("Selected")
                                        }
                                    }.contentShape(Rectangle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(height: 332)
                }
            } else {
                ContentUnavailableView("No Saved Faces", systemImage: "person.crop.rectangle")
                    .frame(height: 332)
            }
            if let failure { Text(failure).foregroundStyle(.red).font(.caption) }
            HStack {
                Text(overview.photoCount == 1 ? "1 photo version" : "\(overview.photoCount) photo versions")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Browse Photos") { model.browsePerson(request) }
                    .disabled(person == nil)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 675)
    }

    private func portrait(_ face: PersonOverview.Face, chosen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            PersonPortraitPreview(face: face).frame(height: 220)
            Text(face.photo.displayName).lineLimit(1).font(.headline)
            if chosen {
                Label("Representative Face", systemImage: "star.fill").foregroundStyle(.secondary)
            } else {
                Button("Use as Representative") {
                    if model.setRepresentativeFace(face, for: request) { failure = nil }
                    else {
                        failure = model.error ?? String(localized: "The representative face could not be saved.")
                        model.error = nil
                    }
                }.disabled(model.busy)
            }
        }
    }
}

struct PersonPortraitPreview: View {
    @EnvironmentObject private var model: Workspace
    let face: PersonOverview.Face
    var compact = false
    @State private var result: PreviewResult?

    private struct PreviewKey: Equatable {
        let faceID: PersonOverview.Face.ID
        let region: FaceRegion
        let digest: String
        let filename: String
        let reference: String?
        let revision: Int
    }

    private struct PreviewResult {
        let key: PreviewKey
        let image: CGImage?
    }

    var body: some View {
        let photo = face.photo
        let key = PreviewKey(faceID: face.id, region: face.face.region, digest: photo.sha256, filename: photo.filename,
                             reference: photo.referencedPath, revision: model.originalStatusRevision)
        Group {
            if let result, result.key == key {
                if let image = result.image {
                    GeometryReader { proxy in
                        Image(decorative: image, scale: 1, orientation: .up)
                            .resizable()
                            .aspectRatio(contentMode: compact ? .fill : .fit)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                    }.accessibilityLabel("Face portrait")
                } else if compact {
                    Image(systemName: "person.crop.rectangle")
                        .font(.largeTitle).foregroundStyle(.secondary)
                } else {
                    ContentUnavailableView("Portrait Unavailable", systemImage: "person.crop.rectangle",
                                           description: Text("The original could not be opened."))
                }
            } else if compact {
                ProgressView().controlSize(.small)
            } else {
                ProgressView("Loading portrait…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .task(id: key) {
            guard let repository = model.repository else { return }
            let image = try? await PersonPortraitLoader.shared.load(photo: photo, region: face.face.region,
                                                                    repository: repository, maximum: compact ? 360 : nil)
            if !Task.isCancelled { result = PreviewResult(key: key, image: image) }
        }
    }
}

private actor PersonPortraitLoader {
    static let shared = PersonPortraitLoader()

    // Serialize original decodes so a screenful of tiles stays within a small working set.
    func load(photo: Photo, region: FaceRegion, repository: LibraryRepository, maximum: Int?) throws -> CGImage? {
        let source = try repository.verifiedFaceSource(for: photo)
        try Task.checkCancellation()
        return FaceDetection.portrait(in: source, region: region, maximum: maximum)
    }
}
