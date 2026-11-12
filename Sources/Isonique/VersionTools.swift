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
        guard let comparisonID else { return nil }
        return library.photos.first { $0.id == comparisonID && $0.trashedAt == nil }
    }

    var comparisonPhotos: [Photo] {
        let active = Dictionary(uniqueKeysWithValues: library.activePhotos.map { ($0.id, $0) })
        return comparisonIDs.compactMap { active[$0] }
    }

    var canPromoteComparisonSelection: Bool {
        guard let comparisonID, let selection else { return false }
        return comparisonID != selection && comparisonIDs.contains(selection)
    }

    var canRemoveComparisonSelection: Bool {
        guard let comparisonID, let selection else { return false }
        return selection != comparisonID && comparisonIDs.contains(selection) && comparisonIDs.count > 2
    }

    var canStartComparison: Bool {
        guard !busy, !isViewingTrash, !quickPreview else { return false }
        if batchMode { return photos.lazy.filter { self.batchSelection.contains($0.id) }.prefix(2).count == 2 }
        guard let selected else { return false }
        return photos.count > 1 || library.photos.contains {
            $0.id != selected.id && $0.originalID == selected.originalID && $0.trashedAt == nil
        }
    }

    func startComparison() {
        guard canStartComparison else { return }
        if batchMode {
            let chosen = photos.filter { batchSelection.contains($0.id) }
            guard chosen.count >= 2 else { return }
            let primary = selection.flatMap { id in chosen.first { $0.id == id } } ?? chosen[0]
            comparisonIDs = [primary.id] + chosen.map(\.id).filter { $0 != primary.id }
            comparisonID = primary.id
            selection = comparisonIDs.first { $0 != primary.id }
            batchMode = false
            batchSelection = []
            viewer = true
            compareOriginal = false
            tool = .select
            return
        }
        guard let selected else { return }
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
        comparisonIDs = [id, selection].compactMap { $0 }.reduce(into: []) {
            if !$0.contains($1) { $0.append($1) }
        }
        viewer = true
        compareOriginal = false
        tool = .select
    }

    func selectBrowserPhoto(_ id: UUID) {
        if comparisonID != nil, !comparisonIDs.contains(id),
           library.activePhotos.contains(where: { $0.id == id }) {
            comparisonIDs.append(id)
        }
        selection = id
    }

    func promoteComparison(_ id: UUID) {
        guard let oldPrimary = comparisonID, id != oldPrimary, comparisonIDs.contains(id) else { return }
        comparisonID = id
        comparisonIDs.removeAll { $0 == id }
        comparisonIDs.insert(id, at: 0)
        if selection == id { selection = oldPrimary }
    }

    func promoteComparisonSelection() {
        guard let selection else { return }
        promoteComparison(selection)
    }

    func removeFromComparison(_ id: UUID) {
        guard id != comparisonID, comparisonIDs.contains(id), comparisonIDs.count > 2 else { return }
        comparisonIDs.removeAll { $0 == id }
        if selection == id || selection == comparisonID {
            selection = comparisonIDs.first { $0 != comparisonID }
        }
    }

    func removeComparisonSelection() {
        guard let selection else { return }
        removeFromComparison(selection)
    }

    func moveComparisonSelection(by delta: Int) {
        guard comparisonIDs.count >= 2 else { return }
        let candidates = comparisonIDs.filter { $0 != comparisonID }
        guard !candidates.isEmpty else { return }
        let current = candidates.firstIndex(where: { $0 == selection }) ?? (delta > 0 ? -1 : candidates.count)
        let next = min(candidates.count - 1, max(0, current + delta))
        selection = candidates[next]
    }

    func stopComparison() {
        comparisonID = nil
        comparisonIDs = []
    }
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
    let photos: [Photo]
    let repository: LibraryRepository
    @State private var navigation = ComparisonNavigationSet()

    var body: some View {
        let ids = photos.map(\.id)
        VStack(spacing: 8) {
            HStack {
                Label("Compare \(photos.count) Photos", systemImage: "rectangle.split.2x1")
                Spacer()
                if model.clipping.enabled { ClippingLegend(settings: model.clipping) }
                Toggle("Synchronize Navigation", isOn: Binding(
                    get: { navigation.synchronized },
                    set: { navigation.setSynchronized($0, primaryID: model.comparisonID,
                                                       visibleIDs: ids) }))
                    .toggleStyle(.switch).controlSize(.small)
                    .help("Use the same zoom and normalized pan position in every pane")
                Button("Done", action: model.stopComparison)
            }.font(.caption).padding(.horizontal, 14).padding(.top, 10)
            GeometryReader { proxy in
                let columnCount = ComparisonLayout.columnCount(width: proxy.size.width,
                                                               photoCount: photos.count)
                let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: columnCount)
                let rows = max(1, Int(ceil(Double(photos.count) / Double(columnCount))))
                let paneHeight = max(240, (proxy.size.height - CGFloat(rows - 1) * 10) / CGFloat(rows))
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                            let primary = photo.id == model.comparisonID
                            let selectIndex = photos.prefix(index).filter { $0.id != model.comparisonID }.count + 1
                            ComparisonPane(photo: photo,
                                title: primary ? "Primary" : "Select \(selectIndex)",
                                repository: repository, navigation: binding(for: photo.id),
                                isPrimary: primary, isActive: photo.id == model.selection,
                                canRemove: !primary && photos.count > 2,
                                select: { model.selection = photo.id },
                                promote: { model.promoteComparison(photo.id) },
                                remove: { model.removeFromComparison(photo.id) })
                                .frame(height: paneHeight)
                        }
                    }
                }
            }.padding(.horizontal, 14).padding(.bottom, 8)
        }.accessibilityElement(children: .contain)
            .onAppear { navigation.retain(ids) }
            .onChange(of: ids) { _, value in navigation.retain(value) }
    }

    private func binding(for id: UUID) -> Binding<ComparisonNavigation> {
        Binding(get: { navigation.value(for: id) }, set: { navigation.update($0, for: id) })
    }
}

enum ComparisonLayout {
    static func columnCount(width: CGFloat, photoCount: Int) -> Int {
        guard photoCount > 0 else { return 1 }
        let available = width.isFinite ? max(0, width) : 0
        let fitting = max(1, Int((available + 10) / 330))
        return min(photoCount, min(3, fitting))
    }
}

struct ComparisonRenderRequest: Equatable {
    let root: URL
    let photoID: UUID
    let filename: String
    let referencedPath: String?
    let adjustments: Adjustments
    let revision: Int
    let profile: Data?
    let maximum: CGFloat?

    init(repository: LibraryRepository, photo: Photo, navigation: ComparisonNavigation,
         revision: Int, profile: Data?) {
        root = repository.root
        photoID = photo.id
        filename = photo.filename
        referencedPath = photo.referencedPath
        adjustments = photo.adjustments
        self.revision = revision
        self.profile = profile
        maximum = navigation.scale == nil ? 1800 : nil
    }
}

enum ComparisonImageLoader {
    static func load(_ photo: Photo, request: ComparisonRenderRequest,
                     repository: LibraryRepository, cache: ViewerRenderCache) async throws -> ViewerImage {
        try Task.checkCancellation()
        let url = try repository.availableOriginalURL(photo)
        let frame = try await cache.frame(url: url, adjustments: request.adjustments,
                                          maximum: request.maximum, revision: request.revision)
        try Task.checkCancellation()
        return try await ViewerImage.prepare(frame.image, proofProfile: request.profile)
    }
}

private struct ComparisonPane: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    let title: String
    let repository: LibraryRepository
    @Binding var navigation: ComparisonNavigation
    let isPrimary: Bool
    let isActive: Bool
    let canRemove: Bool
    let select: () -> Void
    let promote: () -> Void
    let remove: () -> Void
    @State private var image: ViewerImage?
    @State private var failure: String?

    var body: some View {
        let request = ComparisonRenderRequest(repository: repository, photo: photo,
            navigation: navigation, revision: model.originalStatusRevision,
            profile: model.proofEnabled ? model.proofProfile : nil)
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button(action: select) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.caption).foregroundStyle(isPrimary ? Color.accentColor : .secondary)
                        Text(photo.displayName).lineLimit(1).font(.caption.weight(.semibold))
                    }
                }.buttonStyle(.plain)
                Spacer()
                if let scale = navigation.scale {
                    Text(ViewerZoom.percentage(scale)).font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Button(navigation.scale == nil ? "100%" : "Fit") {
                    navigation.toggleActualPixels()
                }.buttonStyle(.plain).font(.caption.monospacedDigit())
                if !isPrimary {
                    Button(action: promote) { Image(systemName: "arrow.up.to.line") }
                        .buttonStyle(.plain).help("Promote to Primary · Option-P")
                }
                if canRemove {
                    Button(action: remove) { Image(systemName: "xmark") }
                        .buttonStyle(.plain).help("Remove from Compare · Option-Delete")
                }
            }
            Group {
                if let image {
                    ComparisonViewport(image: image, model: model, label: photo.displayName,
                                       navigation: $navigation)
                }
                else if let failure { ContentUnavailableView("Image unavailable", systemImage: "exclamationmark.triangle", description: Text(failure)) }
                else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.padding(8).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(isActive ? Color.accentColor : Color.white.opacity(0.08),
                        lineWidth: isActive ? 2 : 1))
            .task(id: request) {
                guard !Task.isCancelled else { return }
                image = nil
                failure = nil
                do {
                    let preview = try await ComparisonImageLoader.load(photo, request: request,
                        repository: repository, cache: model.viewerRenderCache)
                    guard !Task.isCancelled else { return }
                    image = preview
                } catch {
                    if !Task.isCancelled { failure = error.localizedDescription }
                }
            }
    }
}
