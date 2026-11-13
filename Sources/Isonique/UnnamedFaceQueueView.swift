import IsoniqueCore
import SwiftUI

struct UnnamedFaceQueueView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    let review: UnnamedFaceReview
    @State private var scope: UnnamedFaceScope
    @State private var skipped: Set<UnnamedFaceItem.ID> = []

    init(review: UnnamedFaceReview) {
        self.review = review
        _scope = State(initialValue: review.initialScope)
    }

    var body: some View {
        let savedQueue = model.unnamedFaces(in: scope)
        let queue = skipped.isEmpty ? savedQueue : savedQueue.filter { !skipped.contains($0.id) }
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Unnamed Faces").font(.title2.bold())
                Spacer()
                Picker("Scope", selection: $scope) {
                    Text("Entire Library").tag(UnnamedFaceScope.library)
                    ForEach(model.library.projects) { project in
                        Text(project.name).tag(UnnamedFaceScope.project(project.id))
                    }
                }.frame(maxWidth: 290)
            }
            if let item = queue.first {
                HStack(alignment: .top, spacing: 16) {
                    UnnamedFacePreview(item: item)
                        .frame(width: 400, height: 300)
                    UnnamedFaceActions(item: item, scope: scope, review: review, remaining: queue.count) {
                        skipped.insert(item.id)
                    }
                        .id(item.id).frame(width: 245, alignment: .leading)
                }
            } else if !savedQueue.isEmpty {
                ContentUnavailableView {
                    Label("Only Skipped Faces Remain", systemImage: "person.crop.rectangle")
                } actions: {
                    Button("Review Skipped Faces") { skipped.subtract(savedQueue.map(\.id)) }
                }.frame(height: 300)
            } else {
                ContentUnavailableView("No Unnamed Faces", systemImage: "person.crop.rectangle",
                                       description: Text("All saved faces in this scope have been reviewed."))
                    .frame(height: 300)
            }
            HStack {
                Text("Each choice saves immediately and can be undone.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 701)
    }
}

private struct UnnamedFaceActions: View {
    @EnvironmentObject private var model: Workspace
    let item: UnnamedFaceItem
    let scope: UnnamedFaceScope
    let review: UnnamedFaceReview
    let remaining: Int
    let skip: () -> Void
    @State private var existing = ""
    @State private var name = ""
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(item.photo.displayName).font(.headline).lineLimit(2)
            Text("Face \(item.number) of \(item.faceCount)").foregroundStyle(.secondary)
            Text(remaining == 1 ? "1 face remaining" : "\(remaining) faces remaining").foregroundStyle(.secondary)
            Divider()
            if !model.peopleGroups.isEmpty {
                Picker("Existing name", selection: $existing) {
                    Text("Choose a name").tag("")
                    ForEach(model.peopleGroups) { group in
                        Text(group.name).tag(group.id)
                    }
                }
                Button("Assign Existing Name") { resolve(.existingName(existing)) }
                    .disabled(existing.isEmpty)
            }
            TextField("New name", text: $name).textFieldStyle(.roundedBorder)
            Button("Assign New Name") { resolve(.newName(name)) }
                .keyboardShortcut(.defaultAction)
                .disabled(PhotoFace.cleanedName(name).isEmpty)
            Divider()
            HStack {
                Button("Skip", action: skip)
                Button("Dismiss Face", role: .destructive) { resolve(.dismiss) }
            }
            if let failure { Text(failure).font(.caption).foregroundStyle(.red) }
        }.disabled(model.busy)
    }

    private func resolve(_ decision: UnnamedFaceDecision) {
        if !model.resolveUnnamedFace(item, in: scope, review: review, decision: decision) {
            failure = model.error ?? String(localized: "The face could not be saved.")
            model.error = nil
        }
    }
}

private struct UnnamedFacePreview: View {
    @EnvironmentObject private var model: Workspace
    let item: UnnamedFaceItem
    @State private var result: PreviewResult?

    private struct PreviewKey: Equatable {
        let photoID: UUID
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
        let photo = item.photo
        let key = PreviewKey(photoID: photo.id, digest: photo.sha256, filename: photo.filename,
                             reference: photo.referencedPath, revision: model.originalStatusRevision)
        Group {
            if let result, result.key == key {
                if let image = result.image {
                    GeometryReader { proxy in
                        let scale = min(proxy.size.width / CGFloat(image.width), proxy.size.height / CGFloat(image.height))
                        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
                        let rect = item.face.region.rect
                        ZStack(alignment: .topLeading) {
                            Image(decorative: image, scale: 1, orientation: .up)
                                .resizable().frame(width: size.width, height: size.height)
                            Rectangle().strokeBorder(.yellow, lineWidth: 2)
                                .frame(width: rect.width * size.width, height: rect.height * size.height)
                                .offset(x: rect.minX * size.width, y: rect.minY * size.height)
                        }
                        .frame(width: size.width, height: size.height).clipped()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(.black)
                    .accessibilityLabel("Original preview with the current face outlined")
                } else {
                    ContentUnavailableView("Original Unavailable", systemImage: "photo.badge.exclamationmark",
                                           description: Text("You can still name or dismiss the saved face."))
                }
            } else {
                ProgressView("Loading original…")
            }
        }
        .task(id: key) {
            guard let repository = model.repository else { return }
            let task = Task.detached(priority: .userInitiated) { try repository.verifiedFaceSource(for: photo) }
            let image = try? await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
            if !Task.isCancelled { result = PreviewResult(key: key, image: image) }
        }
    }
}
