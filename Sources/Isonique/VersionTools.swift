import SwiftUI
import AppKit
import IsoniqueCore

extension Workspace {
    var canCreateVersion: Bool { !busy && !batchMode && !isViewingTrash && selected != nil }

    func createVersion(from source: VersionSource, of id: UUID? = nil) {
        guard !busy, !batchMode, !isViewingTrash, let id = id ?? selection else { return }
        var draft = library
        guard let version = draft.createVersion(of: id, from: source) else { return }
        var nextHistory = history
        nextHistory.record(.removeVersion(version))
        guard commit(draft, history: nextHistory) else { return }
        revealVersion(version.id)
        status = "Created \(version.displayName) · shares the original"
    }

    func revealVersion(_ id: UUID) {
        if !photos.contains(where: { $0.id == id }) { showBrowser(allPhotos: true) }
        selectBrowserPhoto(id)
        compareOriginal = false
        tool = .select
    }

    func renameVersion(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let version = selected, version.id == id, version.sharedOriginalID != nil else { return }
        edit { $0.versionName = trimmed }
        selectAfterChange(preferred: id)
    }

    var comparisonPhoto: Photo? {
        guard let comparisonID, comparisonID != selection else { return nil }
        return library.photos.first { $0.id == comparisonID && $0.trashedAt == nil }
    }

    var canStartComparison: Bool {
        guard !busy, !batchMode, !isViewingTrash, let selected else { return false }
        return photos.count > 1 || library.photos.contains {
            $0.id != selected.id && $0.originalID == selected.originalID && $0.trashedAt == nil
        }
    }

    func startComparison() {
        guard canStartComparison, let selected else { return }
        let visible = photos
        let sibling = visible.first { $0.id != selected.id && $0.originalID == selected.originalID }
        if let alternate = sibling ?? visible.first(where: { $0.id != selected.id }) {
            selection = alternate.id
            showComparison(reference: selected.id)
        } else if let sibling = library.photos.first(where: {
            $0.id != selected.id && $0.originalID == selected.originalID && $0.trashedAt == nil
        }) {
            showComparison(reference: sibling.id)
        }
    }

    func showComparison(reference id: UUID) {
        guard !busy, !batchMode, !isViewingTrash, selected != nil, selection != id,
              library.photos.contains(where: { $0.id == id && $0.trashedAt == nil }) else { return }
        comparisonID = id
        viewer = true
        compareOriginal = false
        tool = .select
    }

    func selectBrowserPhoto(_ id: UUID) {
        if id == comparisonID { comparisonID = selection }
        selection = id
    }

    func stopComparison() { comparisonID = nil }
}

struct VersionFamilyView: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    @State private var name = ""

    var body: some View {
        let siblings = model.library.activePhotos.filter { $0.originalID == photo.originalID && $0.id != photo.id }
        DisclosureGroup("Photo Versions") {
            VStack(alignment: .leading, spacing: 9) {
                Menu("Create Version") {
                    Button("New Version from Original") { model.createVersion(from: .original) }
                    Button("Duplicate Version") { model.createVersion(from: .current) }
                }.disabled(!model.canCreateVersion)
                if photo.sharedOriginalID != nil {
                    TextField("Version name", text: $name).onSubmit(rename)
                    Button("Rename Version", action: rename)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || name == photo.versionName)
                }
                ForEach(siblings) { sibling in
                    HStack {
                        Button(sibling.displayName) { model.revealVersion(sibling.id) }
                            .lineLimit(1)
                        Spacer()
                        Button("Compare") { model.showComparison(reference: sibling.id) }
                            .disabled(!model.canCreateVersion)
                    }
                }
                Text("Each version has its own edits and metadata. Versions share the original file.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(.top, 8)
        }.onAppear { name = photo.versionName ?? "" }
            .onChange(of: photo.versionName) { _, value in name = value ?? "" }
    }

    private func rename() { model.renameVersion(photo.id, to: name) }
}

struct PhotoComparisonView: View {
    @EnvironmentObject var model: Workspace
    let reference: Photo
    let selected: Photo
    let repository: LibraryRepository

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Compare Photos", systemImage: "rectangle.split.2x1")
                Spacer()
                if model.clipping.enabled { ClippingLegend(settings: model.clipping) }
                Button("Done", action: model.stopComparison)
            }.font(.caption).padding(.horizontal, 14).padding(.top, 10)
            HStack(spacing: 10) {
                ComparisonPane(photo: reference, title: "Reference", repository: repository)
                ComparisonPane(photo: selected, title: "Selected", repository: repository)
            }.padding(.horizontal, 14).padding(.bottom, 8)
        }.accessibilityElement(children: .contain)
    }
}

private struct ComparisonPane: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    let title: String
    let repository: LibraryRepository
    @State private var image: ViewerImage?
    @State private var failure: String?

    private struct Request: Equatable {
        let root: URL
        let photoID: UUID
        let filename: String
        let referencedPath: String?
        let adjustments: Adjustments
        let revision: Int
        let profile: Data?
    }

    var body: some View {
        let request = Request(root: repository.root, photoID: photo.id, filename: photo.filename,
                              referencedPath: photo.referencedPath, adjustments: photo.adjustments,
                              revision: model.originalStatusRevision, profile: model.proofEnabled ? model.proofProfile : nil)
        VStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(photo.displayName).lineLimit(1).font(.caption.weight(.semibold))
            }
            Group {
                if let image {
                    ClippingPreview(image: image).aspectRatio(image.size, contentMode: .fit)
                        .accessibilityLabel(photo.displayName)
                }
                else if let failure { ContentUnavailableView("Image unavailable", systemImage: "exclamationmark.triangle", description: Text(failure)) }
                else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            .task(id: request) {
                guard !Task.isCancelled else { return }
                image = nil
                failure = nil
                do {
                    let url = try repository.availableOriginalURL(photo)
                    let frame = try await model.viewerRenderCache.frame(url: url, adjustments: request.adjustments,
                                                                       maximum: 1800, revision: request.revision)
                    let preview = try await ViewerImage.prepare(frame.image, proofProfile: request.profile)
                    guard !Task.isCancelled else { return }
                    image = preview
                } catch {
                    if !Task.isCancelled { failure = error.localizedDescription }
                }
            }
    }
}
