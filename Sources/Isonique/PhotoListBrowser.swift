import SwiftUI
import AppKit
import IsoniqueCore

enum BrowserPresentation: String, CaseIterable, Identifiable {
    case grid = "Grid Browser"
    case list = "List Browser"
    case places = "Places"
    case viewer = "Photo Viewer"

    var id: Self { self }
    var shortcut: KeyboardShortcut? {
        switch self {
        case .grid: return KeyboardShortcut("g", modifiers: [.control])
        case .list: return KeyboardShortcut("l", modifiers: [.control])
        case .places: return KeyboardShortcut("m", modifiers: [.control])
        case .viewer: return nil
        }
    }

    var icon: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet.rectangle"
        case .places: return "map"
        case .viewer: return "rectangle.bottomthird.inset.filled"
        }
    }
}

enum GridThumbnailSize: String, CaseIterable, Identifiable {
    case compact = "Compact"
    case standard = "Standard"
    case large = "Large"

    static let preferenceKey = "browser.gridThumbnailSize"
    var id: Self { self }

    var columnWidth: CGFloat {
        switch self {
        case .compact: return 132
        case .standard: return 170
        case .large: return 244
        }
    }

    var imageHeight: CGFloat {
        switch self {
        case .compact: return 104
        case .standard: return 140
        case .large: return 190
        }
    }

    var decodeMaximum: Int {
        switch self {
        case .compact: return 256
        case .standard: return 360
        case .large: return 512
        }
    }
}

struct GridThumbnailSizePicker: View {
    @ObservedObject var model: Workspace

    var body: some View {
        Picker("Grid Thumbnail Size", selection: $model.gridThumbnailSize) {
            ForEach(GridThumbnailSize.allCases) { size in
                Text(size.rawValue).tag(size)
            }
        }
    }
}

extension Workspace {
    var usesPlacesPhotos: Bool { places && !batchMode && !isViewingTrash }

    var presentation: BrowserPresentation {
        if viewer { return .viewer }
        return usesPlacesPhotos ? .places : browserLayout
    }

    func canChoosePresentation(_ presentation: BrowserPresentation) -> Bool {
        guard !busy, repository != nil else { return false }
        switch presentation {
        case .places: return !batchMode && !isViewingTrash
        case .viewer: return !batchMode
        case .grid, .list: return true
        }
    }

    func setBrowserLayout(_ layout: BrowserPresentation) {
        guard layout == .grid || layout == .list else { return }
        browserLayout = layout
        preferences.set(layout.rawValue, forKey: "browser.layout")
    }

    func choosePresentation(_ presentation: BrowserPresentation) {
        guard canChoosePresentation(presentation) else { return }
        switch presentation {
        case .viewer:
            guard !photos.isEmpty else { return }
            if selected == nil { selection = photos.first?.id }
            viewer = true
        case .places:
            showBrowser()
            places = true
            selectAfterChange(preferred: selection)
        case .grid, .list:
            let wasInPlaces = usesPlacesPhotos
            places = false
            setBrowserLayout(presentation)
            showBrowser()
            if wasInPlaces { selectAfterChange(preferred: selection) }
        }
    }

    func setListSelection(_ ids: Set<UUID>) {
        let chosen = photos.filter { ids.contains($0.id) }
        batchSelection = Set(chosen.map(\.id))
        if selection.map(batchSelection.contains) != true { selection = chosen.first?.id }
    }

    func openListPhoto(_ id: UUID) {
        guard !batchMode, photos.contains(where: { $0.id == id }) else { return }
        selectBrowserPhoto(id)
        choosePresentation(.viewer)
    }
}

struct PhotoListBrowser: View {
    @ObservedObject var model: Workspace
    let photos: [Photo]

    var body: some View {
        Group {
            if model.batchMode {
                Table(photos, selection: Binding(get: { model.batchSelection }, set: model.setListSelection)) { columns }
            } else {
                Table(photos, selection: $model.selection) { columns }
            }
        }
        .environment(\.defaultMinListRowHeight, 30)
        .accessibilityLabel("Photo list")
        .keywordShortcuts(for: model)
        .onKeyPress(keys: ["0", "1", "2", "3", "4", "5", "9", "=", "-", "/"], phases: .down, action: model.reviewKey)
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, ids.count == 1, let photo = photos.first(where: { $0.id == id }) {
                if !model.batchMode { Button("Open Photo") { model.openListPhoto(id) } }
                PhotoContextActions(model: model, photo: photo, url: try? model.repository?.availableOriginalURL(photo))
            } else if !ids.isEmpty {
                Button(model.isViewingTrash ? "Put Back Photos" : "Move Photos to Trash") {
                    model.setPhotosTrashed(ids, trashed: !model.isViewingTrash)
                }
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first { model.openListPhoto(id) }
        }
    }

    @TableColumnBuilder<Photo, Never>
    private var columns: some TableColumnContent<Photo, Never> {
        TableColumn("Photo") { photo in
            HStack(spacing: 7) {
                if let url = try? model.repository?.availableOriginalURL(photo) {
                    Thumbnail(request: .init(photoID: photo.id, url: url, adjustments: photo.adjustments,
                                             maximum: 96, revision: model.originalStatusRevision),
                              cache: model.thumbnailCache).frame(width: 34, height: 25)
                } else {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                        .accessibilityLabel("Original unavailable").frame(width: 34)
                }
                Text(photo.displayName).lineLimit(1)
                if let stackID = photo.stackID { StackBadge(stackID: stackID, photo: photo, model: model) }
            }
        }.width(min: 150, ideal: 245)
        TableColumn("Rating") { photo in
            if photo.rating == RatingRules.rejected {
                Text("Rejected").foregroundStyle(.secondary)
            } else if photo.rating > 0 {
                Text(RatingRules.stars(photo.rating)).foregroundStyle(.orange)
                    .accessibilityLabel("\(photo.rating) stars")
            } else {
                Text("Unrated").foregroundStyle(.secondary)
            }
        }.width(min: 72, ideal: 88)
        TableColumn("Label") { photo in
            if let label = photo.colorLabel {
                Label(model.name(for: label), systemImage: "circle.fill").foregroundStyle(label.tint).lineLimit(1)
            }
        }.width(min: 58, ideal: 90)
        TableColumn("Flag") { photo in
            if photo.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange).accessibilityLabel("Flagged") }
        }.width(42)
        TableColumn("Captured", value: \.captureDate).width(min: 115, ideal: 160)
        TableColumn("Camera", value: \.camera).width(min: 75, ideal: 120)
    }
}

struct PhotoContextActions: View {
    @ObservedObject var model: Workspace
    let photo: Photo
    let url: URL?

    var body: some View {
        Button(model.isViewingTrash ? "Put Back" : "Move to Trash") {
            model.setPhotosTrashed([photo.id], trashed: !model.isViewingTrash)
        }
        if !model.isViewingTrash {
            StackContextActions(model: model, photo: photo)
            Button("New Version from Original") { model.createVersion(from: .original, of: photo.id) }.disabled(model.batchMode)
            Button("Duplicate Version") { model.createVersion(from: .current, of: photo.id) }.disabled(model.batchMode)
            Button("Edit with External Editor…") { model.editWithExternalEditor(photoID: photo.id) }
                .disabled(model.batchMode || model.busy || model.externalEditHandoff != nil || url == nil)
            if model.selection != photo.id {
                Button("Compare with Selected") { model.showComparison(reference: photo.id) }.disabled(!model.canCreateVersion)
            }
            Divider()
            if let url { Button("Reveal Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            if photo.referencedPath != nil || url == nil {
                Button("Relink Original…") { model.relinkOriginalPanel(photo) }
            }
            if photo.referencedPath != nil, url != nil {
                Button("Consolidate Original") { model.consolidateOriginal(photo) }
            }
        }
    }
}
