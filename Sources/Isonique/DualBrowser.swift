import SwiftUI
import IsoniqueCore

enum BrowserPaneFocus: String {
    case primary, secondary
}

struct SecondaryBrowserConfiguration: Codable, Equatable {
    var visible = false
    var scope = "all"
    var search = ""
    var sort = PhotoSort.imported
    var descending = false
    private var ratingValue = RatingFilter.all.rawValue

    var rating: RatingFilter {
        get { RatingFilter(rawValue: ratingValue) ?? .all }
        set { ratingValue = newValue.rawValue }
    }

    private enum CodingKeys: String, CodingKey { case visible, scope, search, sort, descending, ratingValue }

    init() {}

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        visible = try values.decodeIfPresent(Bool.self, forKey: .visible) ?? false
        scope = try values.decodeIfPresent(String.self, forKey: .scope) ?? "all"
        search = try values.decodeIfPresent(String.self, forKey: .search) ?? ""
        sort = try values.decodeIfPresent(PhotoSort.self, forKey: .sort) ?? .imported
        descending = try values.decodeIfPresent(Bool.self, forKey: .descending) ?? false
        ratingValue = try values.decodeIfPresent(Int.self, forKey: .ratingValue) ?? RatingFilter.all.rawValue
    }
}

enum SecondaryBrowserPreferences {
    static let key = "browser.secondary.configuration.v1"

    static func load(from preferences: UserDefaults) -> SecondaryBrowserConfiguration {
        guard let data = preferences.data(forKey: key),
              let value = try? JSONDecoder().decode(SecondaryBrowserConfiguration.self, from: data) else {
            return SecondaryBrowserConfiguration()
        }
        return value
    }

    static func save(_ value: SecondaryBrowserConfiguration, to preferences: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) { preferences.set(data, forKey: key) }
    }
}

struct BrowserScopeOption: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
}

extension Workspace {
    var secondaryScopeOptions: [BrowserScopeOption] {
        var options = [BrowserScopeOption(id: "all", title: "All Photos", symbol: "photo.on.rectangle.angled"),
                       BrowserScopeOption(id: "flagged", title: "Flagged", symbol: "flag"),
                       BrowserScopeOption(id: "people", title: "People", symbol: "person.crop.rectangle")]
        options += peopleGroups.map { BrowserScopeOption(id: $0.scope, title: $0.name, symbol: "person") }
        options += library.projects.map { BrowserScopeOption(id: "project:\($0.id)", title: $0.name, symbol: "folder") }
        options += activeStacks.keys.sorted { $0.uuidString < $1.uuidString }.map { id in
            let members = activeStacks[id] ?? []
            let pick = library.stackBrowser?.preferredPick(stackID: id, albumID: nil, members: members) ?? members.first
            return BrowserScopeOption(id: "stack:\(id)", title: pick?.displayName ?? "Photo Stack",
                                      symbol: "square.3.layers.3d")
        }
        options += library.albums.map {
            BrowserScopeOption(id: "album:\($0.id)", title: $0.name,
                               symbol: $0.rule == nil ? "rectangle.stack" : "gearshape.2")
        }
        return options
    }

    var normalizedSecondaryScope: String {
        secondaryScopeOptions.contains(where: { $0.id == secondaryBrowser.scope }) ? secondaryBrowser.scope : "all"
    }

    var secondaryPhotos: [Photo] {
        filteredPhotos(scope: normalizedSecondaryScope, search: secondaryBrowser.search,
                       sort: secondaryBrowser.sort, descending: secondaryBrowser.descending,
                       rating: secondaryBrowser.rating, originals: .all, color: .all)
    }

    var secondarySelected: Photo? {
        guard let id = secondaryBrowserSelection else { return nil }
        return secondaryPhotos.first { $0.id == id }
    }

    var secondaryTitle: String {
        secondaryScopeOptions.first { $0.id == normalizedSecondaryScope }?.title ?? "All Photos"
    }

    var canShowSecondaryBrowser: Bool {
        !busy && repository != nil && activeLightTable == nil && !viewer && !places && !batchMode && !isPeopleGallery
    }

    func setSecondaryBrowserVisible(_ visible: Bool) {
        guard !visible || canShowSecondaryBrowser else { return }
        secondaryBrowser.visible = visible
        if visible {
            if normalizedSecondaryScope != secondaryBrowser.scope { secondaryBrowser.scope = "all" }
            if secondaryBrowserSelection.flatMap({ id in secondaryPhotos.first { $0.id == id } }) == nil {
                secondaryBrowserSelection = secondaryPhotos.first?.id
            }
        } else if activeBrowserPane == .secondary {
            activeBrowserPane = .primary
        }
    }

    func toggleSecondaryBrowser() { setSecondaryBrowserVisible(!secondaryBrowser.visible) }

    func setSecondaryScope(_ scope: String) {
        guard secondaryScopeOptions.contains(where: { $0.id == scope }) else { return }
        secondaryBrowser.scope = scope
        secondaryBrowserSelection = secondaryPhotos.first?.id
        activeBrowserPane = .secondary
    }

    func manualOrderScope(for scope: String) -> String? {
        if scope == "all" { return scope }
        if scope.hasPrefix("project:"), library.projects.contains(where: { "project:\($0.id)" == scope }) { return scope }
        guard scope.hasPrefix("album:"), let id = UUID(uuidString: String(scope.dropFirst(6))),
              library.albums.first(where: { $0.id == id })?.rule == nil else { return nil }
        return scope
    }

    func canManuallyOrder(_ scope: String) -> Bool {
        !busy && manualOrderScope(for: scope) != nil && repository != nil
    }

    func manualMoveIDs(for photo: Photo, scope: String) -> [UUID] {
        guard let stackID = photo.stackID, library.stackBrowser?.collapsed.contains(stackID) == true,
              !scope.hasPrefix("stack:") else { return [photo.id] }
        return manualOrderSeed(for: scope).filter { $0.stackID == stackID }.map(\.id)
    }

    func manualDropTargetID(for photo: Photo, scope: String) -> UUID {
        manualMoveIDs(for: photo, scope: scope).first ?? photo.id
    }

    func moveManualPhotos(_ ids: [UUID], before target: UUID?, scope: String, secondary: Bool = false) {
        guard let orderScope = manualOrderScope(for: scope), canManuallyOrder(scope) else { return }
        let seed = manualOrderSeed(for: orderScope).map(\.id)
        var draft = library
        var state = draft.browserOrders ?? BrowserOrderState()
        guard state.move(ids, before: target, in: orderScope, seededBy: seed) else { return }
        let previous = draft.browserOrders
        draft.browserOrders = state
        var nextHistory = history
        nextHistory.record(.browserOrders(previous))
        guard commit(draft, history: nextHistory) else { return }
        if secondary {
            secondaryBrowser.sort = .manual
            secondaryBrowser.descending = false
        } else {
            sort = .manual
            sortDescending = false
        }
        status = "Browser order updated"
    }

    func moveManualPhoto(_ photo: Photo, toEnd: Bool, scope: String, secondary: Bool = false) {
        let moving = manualMoveIDs(for: photo, scope: scope)
        let remaining = manualOrderSeed(for: scope).map(\.id).filter { !moving.contains($0) }
        moveManualPhotos(moving, before: toEnd ? nil : remaining.first, scope: scope, secondary: secondary)
    }

    func showSecondaryPhotoInPrimary(_ photo: Photo, openViewer: Bool = false) {
        activeBrowserPane = .primary
        if !photos.contains(where: { $0.id == photo.id }) {
            scope = normalizedSecondaryScope
            search = secondaryBrowser.search
            sort = secondaryBrowser.sort
            sortDescending = secondaryBrowser.descending
            ratingFilter = secondaryBrowser.rating
            originalFilter = .all
            colorFilter = .all
            advancedSearch = nil
        }
        selection = photo.id
        if openViewer { choosePresentation(.viewer) }
    }

    private func manualOrderSeed(for scope: String) -> [Photo] {
        filteredPhotos(scope: scope, search: "", sort: .imported, descending: false,
                       rating: .all, originals: .all, color: .all, includingCollapsed: true)
    }
}

struct SecondaryBrowserPane: View {
    @ObservedObject var model: Workspace

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Second Browser", systemImage: "rectangle.split.2x1")
                        .font(.headline)
                    Spacer()
                    Button { model.setSecondaryBrowserVisible(false) } label: {
                        Image(systemName: "xmark").accessibilityLabel("Hide Second Browser")
                    }.buttonStyle(.plain)
                }
                Picker("Second Browser Scope", selection: Binding(get: { model.normalizedSecondaryScope },
                    set: model.setSecondaryScope)) {
                    ForEach(model.secondaryScopeOptions) { option in
                        Label(option.title, systemImage: option.symbol).tag(option.id)
                    }
                }.labelsHidden()
                TextField("Search this Browser", text: Binding(get: { model.secondaryBrowser.search }, set: {
                    model.secondaryBrowser.search = $0
                    model.secondaryBrowserSelection = model.secondaryPhotos.first?.id
                }))
                HStack {
                    Picker("Rating", selection: Binding(get: { model.secondaryBrowser.rating }, set: {
                        model.secondaryBrowser.rating = $0
                        model.secondaryBrowserSelection = model.secondaryPhotos.first?.id
                    })) {
                        ForEach(RatingFilter.allCases) { Text($0.label).tag($0) }
                    }.labelsHidden()
                    Menu {
                        Picker("Sort by", selection: $model.secondaryBrowser.sort) {
                            ForEach(PhotoSort.allCases) { choice in
                                Text(choice.rawValue).tag(choice)
                                    .disabled(choice == .manual && !model.canManuallyOrder(model.normalizedSecondaryScope))
                            }
                        }
                        Toggle("Descending", isOn: $model.secondaryBrowser.descending)
                    } label: { Image(systemName: "arrow.up.arrow.down") }
                }
            }.padding(12)
            Divider()
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 10)], spacing: 10) {
                    ForEach(model.secondaryPhotos) { photo in
                        SecondaryBrowserPhotoCell(model: model, photo: photo)
                    }
                }.padding(10)
            }
            Divider()
            Text("\(model.secondaryPhotos.count) photos · \(model.activeBrowserPane == .secondary ? "active" : "click to focus")")
                .font(.caption2).foregroundStyle(.secondary).padding(8)
        }
        .frame(minWidth: 240, idealWidth: 310, maxWidth: 430)
        .background(Color(nsColor: .underPageBackgroundColor))
        .accessibilityLabel("Second Browser")
        .simultaneousGesture(TapGesture().onEnded { model.activeBrowserPane = .secondary })
    }
}

private struct SecondaryBrowserPhotoCell: View {
    @ObservedObject var model: Workspace
    let photo: Photo

    var body: some View {
        let selected = model.secondaryBrowserSelection == photo.id
        Button {
            model.secondaryBrowserSelection = photo.id
            model.activeBrowserPane = .secondary
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                BrowserThumbnail(photo: photo, original: try? model.repository?.availableOriginalURL(photo), maximum: 256)
                    .frame(height: 82).clipShape(RoundedRectangle(cornerRadius: 7))
                Text(photo.displayName).font(.caption).lineLimit(1)
                Text(photo.rating == RatingRules.rejected ? "Rejected" : RatingRules.stars(photo.rating))
                    .font(.caption2).foregroundStyle(.orange).frame(height: 11)
                    .accessibilityHidden(true)
            }.padding(6)
                .background(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.04),
                            in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .photoReviewAccessibility(photo, selected: selected)
        .draggable(photo.id.uuidString)
        .dropDestination(for: String.self) { values, _ in
            guard let value = values.first, let id = UUID(uuidString: value),
                  model.canManuallyOrder(model.normalizedSecondaryScope) else { return false }
            let source = model.library.photos.first { $0.id == id }
            let moving = source.map { model.manualMoveIDs(for: $0, scope: model.normalizedSecondaryScope) } ?? [id]
            model.moveManualPhotos(moving, before: model.manualDropTargetID(for: photo,
                scope: model.normalizedSecondaryScope), scope: model.normalizedSecondaryScope, secondary: true)
            return true
        }
        .contextMenu {
            Button("Show in Primary Browser") { model.showSecondaryPhotoInPrimary(photo) }
            Button("Open in Viewer") { model.showSecondaryPhotoInPrimary(photo, openViewer: true) }
            Divider()
            Button("Move to Beginning") { model.moveManualPhoto(photo, toEnd: false,
                scope: model.normalizedSecondaryScope, secondary: true) }
                .disabled(!model.canManuallyOrder(model.normalizedSecondaryScope))
            Button("Move to End") { model.moveManualPhoto(photo, toEnd: true,
                scope: model.normalizedSecondaryScope, secondary: true) }
                .disabled(!model.canManuallyOrder(model.normalizedSecondaryScope))
        }
    }
}
