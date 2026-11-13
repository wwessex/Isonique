import SwiftUI
import AppKit
import IsoniqueCore

enum PhotoListColumn: String, CaseIterable, Identifiable {
    case photo, rating, label, flag, captured, camera
    case lens, iso, aperture, shutterSpeed, focalLength, dimensions, caption, keywords

    var id: String { rawValue }
    var title: String {
        switch self {
        case .photo: return "Photo"
        case .rating: return "Rating"
        case .label: return "Label"
        case .flag: return "Flag"
        case .captured: return "Captured"
        case .camera: return "Camera"
        case .lens: return "Lens"
        case .iso: return "ISO"
        case .aperture: return "Aperture"
        case .shutterSpeed: return "Shutter Speed"
        case .focalLength: return "Focal Length"
        case .dimensions: return "Dimensions"
        case .caption: return "Caption"
        case .keywords: return "Keywords"
        }
    }
    var localizedTitle: String { Bundle.main.localizedString(forKey: title, value: nil, table: nil) }
    var defaultVisible: Bool {
        switch self {
        case .photo, .rating, .label, .flag, .captured, .camera: return true
        default: return false
        }
    }
    var minimumWidth: CGFloat {
        switch self {
        case .photo: return 150
        case .rating: return 72
        case .label: return 58
        case .flag: return 42
        case .captured: return 115
        case .camera: return 75
        case .lens: return 90
        case .iso: return 52
        case .aperture: return 64
        case .shutterSpeed: return 80
        case .focalLength: return 78
        case .dimensions: return 92
        case .caption, .keywords: return 100
        }
    }
    var idealWidth: CGFloat {
        switch self {
        case .photo: return 245
        case .rating: return 88
        case .label: return 90
        case .flag: return 42
        case .captured: return 160
        case .camera: return 120
        case .lens: return 180
        case .iso: return 70
        case .aperture: return 82
        case .shutterSpeed: return 105
        case .focalLength: return 96
        case .dimensions: return 115
        case .caption, .keywords: return 220
        }
    }

    func value(for photo: Photo) -> String {
        switch self {
        case .photo: return photo.displayName
        case .rating:
            if photo.rating == RatingRules.rejected { return String(localized: "Rejected") }
            return photo.rating > 0 ? RatingRules.stars(photo.rating) : String(localized: "Unrated")
        case .label: return photo.colorLabel?.title ?? ""
        case .flag: return photo.flagged ? String(localized: "Flagged") : ""
        case .captured: return photo.captureDate
        case .camera: return photo.camera
        case .lens: return photo.cameraEXIF?.lens ?? ""
        case .iso: return photo.cameraEXIF?.iso.map { String($0) } ?? ""
        case .aperture: return photo.cameraEXIF?.fNumber.map { "ƒ/\(Self.decimal($0))" } ?? ""
        case .shutterSpeed: return photo.cameraEXIF?.exposureSeconds.map(Self.shutterSpeed) ?? ""
        case .focalLength: return photo.cameraEXIF?.focalLengthMM.map { "\(Self.decimal($0)) mm" } ?? ""
        case .dimensions: return "\(photo.width) × \(photo.height)"
        case .caption: return photo.caption
        case .keywords: return photo.keywords
        }
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...2)))
    }

    private static func shutterSpeed(_ seconds: Double) -> String {
        let reciprocal = 1 / seconds
        if reciprocal.isFinite, reciprocal >= 2 {
            let denominator = reciprocal.rounded()
            if abs(reciprocal - denominator) / reciprocal < 0.005 {
                return "1/\(Int(denominator)) s"
            }
        }
        return "\(seconds.formatted(.number.grouping(.never).precision(.significantDigits(1...6)))) s"
    }
}

enum ListColumnPreferences {
    static let key = "browser.list.columnCustomization.v1"

    static func load(from preferences: UserDefaults) -> TableColumnCustomization<Photo> {
        guard let data = preferences.data(forKey: key),
              let value = try? JSONDecoder().decode(TableColumnCustomization<Photo>.self, from: data) else {
            return TableColumnCustomization()
        }
        return value
    }

    static func save(_ value: TableColumnCustomization<Photo>, to preferences: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) { preferences.set(data, forKey: key) }
    }
}

enum QuickPreviewPolicy {
    static let maximumDimension = 1600
}

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
    var canToggleQuickPreview: Bool {
        !busy && repository != nil && activeLightTable == nil && comparisonID == nil &&
            !usesPlacesPhotos && !photos.isEmpty
    }

    func setQuickPreview(_ active: Bool) {
        guard !active || canToggleQuickPreview else { return }
        if active {
            tool = .select
            compareOriginal = false
            curveSampling = nil
            whiteBalanceSampling = nil
            targetedColorSampling = nil
            showLoupe = false
        }
        quickPreview = active
    }

    func toggleQuickPreview() {
        setQuickPreview(!quickPreview)
    }

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
            setQuickPreview(false)
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

    func listColumnIsVisible(_ column: PhotoListColumn) -> Bool {
        let visibility = listColumnCustomization[visibility: column.id]
        if visibility == .visible { return true }
        if visibility == .hidden { return false }
        return column.defaultVisible
    }

    func setListColumn(_ column: PhotoListColumn, visible: Bool) {
        guard column != .photo else { return }
        var customization = listColumnCustomization
        customization[visibility: column.id] = visible ? .visible : .hidden
        listColumnCustomization = customization
    }

    func resetListColumns() {
        listColumnCustomization = TableColumnCustomization()
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
                Table(photos, selection: Binding(get: { model.batchSelection }, set: model.setListSelection),
                      columnCustomization: $model.listColumnCustomization) { columns }
            } else {
                Table(photos, selection: $model.selection,
                      columnCustomization: $model.listColumnCustomization) { columns }
            }
        }
        .environment(\.defaultMinListRowHeight, 30)
        .accessibilityLabel("Photo list")
        .keywordShortcuts(for: model)
        .onChange(of: model.selection) { _, _ in model.activeBrowserPane = .primary }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, ids.count == 1, let photo = photos.first(where: { $0.id == id }) {
                if !model.batchMode { Button("Open Photo") { model.openListPhoto(id) } }
                PhotoContextActions(model: model, photo: photo, url: try? model.repository?.availableOriginalURL(photo))
                Divider()
                Button("Move to Beginning") { model.moveManualPhoto(photo, toEnd: false, scope: model.scope) }
                    .disabled(!model.canManuallyOrder(model.scope))
                Button("Move to End") { model.moveManualPhoto(photo, toEnd: true, scope: model.scope) }
                    .disabled(!model.canManuallyOrder(model.scope))
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
        TableColumnForEach(PhotoListColumn.allCases) { column in
            TableColumn(Text(column.localizedTitle)) { photo in
                columnCell(column, photo: photo)
            }
            .width(min: column.minimumWidth, ideal: column.idealWidth)
            .customizationID(column.id)
            .defaultVisibility(column.defaultVisible ? .visible : .hidden)
            .disabledCustomizationBehavior(column == .photo ? .visibility : [])
        }
    }

    @ViewBuilder
    private func columnCell(_ column: PhotoListColumn, photo: Photo) -> some View {
        switch column {
        case .photo:
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
            .draggable(photo.id.uuidString)
            .dropDestination(for: String.self) { values, _ in
                guard let value = values.first, let id = UUID(uuidString: value),
                      model.canManuallyOrder(model.scope) else { return false }
                let source = model.library.photos.first { $0.id == id }
                let moving = source.map { model.manualMoveIDs(for: $0, scope: model.scope) } ?? [id]
                model.moveManualPhotos(moving, before: model.manualDropTargetID(for: photo, scope: model.scope),
                                       scope: model.scope)
                return true
            }
        case .rating:
            if photo.rating == RatingRules.rejected {
                Text("Rejected").foregroundStyle(.secondary)
            } else if photo.rating > 0 {
                Text(RatingRules.stars(photo.rating)).foregroundStyle(.orange)
                    .accessibilityLabel("\(photo.rating) stars")
            } else {
                Text("Unrated").foregroundStyle(.secondary)
            }
        case .label:
            if let label = photo.colorLabel {
                Label(model.name(for: label), systemImage: "circle.fill").foregroundStyle(label.tint).lineLimit(1)
            }
        case .flag:
            if photo.flagged { Image(systemName: "flag.fill").foregroundStyle(.orange).accessibilityLabel("Flagged") }
        case .captured:
            Text(photo.captureDate).lineLimit(1).truncationMode(.tail)
        case .camera:
            Text(photo.camera).lineLimit(1).truncationMode(.tail)
        case .lens, .caption, .keywords:
            Text(column.value(for: photo)).lineLimit(1).truncationMode(.tail)
        case .iso, .aperture, .shutterSpeed, .focalLength, .dimensions:
            Text(column.value(for: photo)).monospacedDigit().lineLimit(1)
        }
    }
}

struct ListColumnEditorView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Customize List Columns").font(.title2.bold())
            Text("Choose visible metadata here. Drag column headers in the List Browser to reorder them or change their width.")
                .foregroundStyle(.secondary)
            List(PhotoListColumn.allCases) { column in
                Toggle(column.localizedTitle, isOn: Binding(get: { model.listColumnIsVisible(column) },
                    set: { model.setListColumn(column, visible: $0) }))
                    .disabled(column == .photo)
            }
            HStack {
                Button("Reset to Defaults", action: model.resetListColumns)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 520, height: 610)
    }
}

struct QuickPreviewPhotoViewer: View {
    @EnvironmentObject private var model: Workspace
    let photo: Photo
    let url: URL

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            Thumbnail(request: .init(photoID: photo.id, url: url, adjustments: photo.adjustments,
                                     maximum: QuickPreviewPolicy.maximumDimension,
                                     revision: model.originalStatusRevision),
                      cache: model.thumbnailCache)
                .padding(22)
        }
        .overlay(alignment: .top) {
            HStack(spacing: 9) {
                Image(systemName: "bolt.fill")
                Text("Quick Preview").fontWeight(.semibold)
                Text(photo.displayName).foregroundStyle(.secondary).lineLimit(1)
            }
            .font(.caption).foregroundStyle(.yellow)
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(.ultraThinMaterial, in: Capsule()).padding(16)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.yellow.opacity(0.8), lineWidth: 2).padding(8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Preview of \(photo.displayName)")
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
            Button("Review Faces…") { model.openPeopleReview(photo) }.disabled(model.busy)
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
