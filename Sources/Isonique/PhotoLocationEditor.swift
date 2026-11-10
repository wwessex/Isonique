import IsoniqueCore
import SwiftUI

enum PhotoLocationAction {
    case assign, clear, useOriginal

    var title: LocalizedStringKey {
        switch self {
        case .assign: return "Assign Location"
        case .clear: return "Clear Location"
        case .useOriginal: return "Use Original Location"
        }
    }

    func includes(_ photo: Photo) -> Bool {
        switch self {
        case .assign: return true
        case .clear: return photo.cataloguedLocation != nil || !photo.hasCataloguedLocation
        case .useOriginal: return photo.locationOverride != nil
        }
    }
}

struct PhotoLocationEdit: Identifiable {
    let id = UUID()
    let action: PhotoLocationAction
    let libraryRoot: URL
    let photos: [Photo]

    func changes(to coordinates: GPSCoordinates?) -> [PhotoLocationChange] {
        photos.compactMap { photo in
            guard action.includes(photo) else { return nil }
            let override: PhotoLocationOverride?
            switch action {
            case .assign:
                guard let coordinates, coordinates != photo.cataloguedLocation else { return nil }
                override = .assigned(coordinates)
            case .clear: override = .cleared
            case .useOriginal: override = nil
            }
            return PhotoLocationChange(photoID: photo.id, location: override)
        }
    }
}

extension Workspace {
    func canEditLocation(_ action: PhotoLocationAction) -> Bool {
        metadataEditingTargets.contains(where: action.includes)
    }

    func openLocationEditor(_ action: PhotoLocationAction) {
        let targets = metadataEditingTargets
        guard let repository, targets.contains(where: action.includes) else { return }
        locationEditor = PhotoLocationEdit(action: action, libraryRoot: repository.root, photos: targets)
    }

    @discardableResult
    func applyLocationEdit(_ edit: PhotoLocationEdit, coordinates: GPSCoordinates?) -> Bool {
        guard !busy else { return false }
        let targets = metadataEditingTargets
        let previousPhotos = Dictionary(uniqueKeysWithValues: edit.photos.map { ($0.id, $0) })
        guard repository?.root == edit.libraryRoot, targets.count == previousPhotos.count, targets.allSatisfy({ photo in
            guard let previous = previousPhotos[photo.id] else { return false }
            return photo.locationOverride == previous.locationOverride && photo.gpsIndex == previous.gpsIndex
        }) else {
            error = "The library, selection or location has changed. Reopen the location editor to review it."
            return false
        }

        let changes = edit.changes(to: coordinates)
        var draft = library
        guard let previous = draft.replaceLocations(changes) else { return false }
        var nextHistory = history
        nextHistory.record(.locations(previous))
        guard commit(draft, history: nextHistory) else { return false }
        if selected == nil { selectAfterChange(preferred: selection) }
        batchSelection.formIntersection(photos.map(\.id))
        status = changes.count == 1 ? "Updated location for 1 photo" : "Updated locations for \(changes.count) photos"
        return true
    }
}

struct PhotoLocationCommands: View {
    @ObservedObject var model: Workspace

    var body: some View {
        Button("Assign Location…") { model.openLocationEditor(.assign) }
            .disabled(!model.canEditLocation(.assign))
        Button("Clear Location…") { model.openLocationEditor(.clear) }
            .disabled(!model.canEditLocation(.clear))
        Button("Use Original Location…") { model.openLocationEditor(.useOriginal) }
            .disabled(!model.canEditLocation(.useOriginal))
    }
}

struct PhotoLocationDraft {
    var latitude: String
    var longitude: String

    var coordinates: GPSCoordinates? { GPSCoordinates(latitude: latitude, longitude: longitude) }

    init(_ point: GPSCoordinates? = nil) {
        let format = FloatingPointFormatStyle<Double>.number.locale(Locale(identifier: "en_US_POSIX"))
            .grouping(.never).precision(.fractionLength(0...16))
        latitude = point?.latitude.formatted(format) ?? ""
        longitude = point?.longitude.formatted(format) ?? ""
    }
}

struct PhotoLocationEditor: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    let edit: PhotoLocationEdit
    @State private var draft: PhotoLocationDraft
    @State private var showsMap = false
    @State private var mapSelection = UUID()
    @State private var searchText = ""
    @State private var chosenResult: PhotoLocationLookupResult?
    @StateObject private var lookup = PhotoLocationLookup()
    @FocusState private var searchFocused: Bool

    init(edit: PhotoLocationEdit) {
        self.edit = edit
        let current = edit.photos.count == 1 ? edit.photos.first?.cataloguedLocation : nil
        _draft = State(initialValue: PhotoLocationDraft(current))
    }

    var body: some View {
        let coordinates = draft.coordinates
        let count = edit.photos.count
        let changes = edit.changes(to: coordinates).count
        VStack(alignment: .leading, spacing: 14) {
            Text(edit.action.title).font(.title2.bold())
            Text(count == 1 ? (edit.photos.first?.displayName ?? "") : "\(count) selected photos")
                .foregroundStyle(.secondary)
            switch edit.action {
            case .assign:
                locationSearch
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Latitude")
                        TextField("Latitude", text: $draft.latitude, prompt: Text("51.5"))
                            .labelsHidden().accessibilityLabel("Latitude")
                    }
                    GridRow {
                        Text("Longitude")
                        TextField("Longitude", text: $draft.longitude, prompt: Text("-0.125"))
                            .labelsHidden().accessibilityLabel("Longitude")
                    }
                }
                Text("Enter signed decimal degrees. Latitude runs from −90 to 90 and longitude from −180 to 180.")
                    .font(.caption).foregroundStyle(.secondary)
                DisclosureGroup("Pick on Map", isExpanded: $showsMap) {
                    if showsMap {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Click a point to place the preview pin. Pan or zoom to refine it.")
                                .font(.caption).foregroundStyle(.secondary)
                            PhotoLocationMap(point: coordinates,
                                             locations: Set(edit.photos.compactMap(\.cataloguedLocation))) {
                                draft = PhotoLocationDraft($0)
                            }.id(mapSelection).frame(height: 295).clipShape(.rect(cornerRadius: 8))
                        }.padding(.top, 6)
                    }
                }
            case .clear:
                Text("Remove these locations from Places and GPS coordinate searches.")
            case .useOriginal:
                Text("Remove the catalogue edits and use the original GPS where available.")
            }
            Text("This changes the catalogue only. The original file and its embedded GPS are preserved.")
                .font(.caption).foregroundStyle(.secondary)
            Text(changes == 1 ? "1 photo will change" : "\(changes) photos will change")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(edit.action.title) {
                    if model.applyLocationEdit(edit, coordinates: coordinates) || model.error != nil { dismiss() }
                }.keyboardShortcut(searchFocused ? nil : .defaultAction).disabled(changes == 0)
            }
        }.padding(24).frame(width: showsMap ? 570 : 450)
            .onDisappear(perform: lookup.cancel)
    }

    private var locationSearch: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Address or place name", text: $searchText, prompt: Text("Address or place name"))
                    .labelsHidden().accessibilityLabel("Address or place name")
                    .focused($searchFocused)
                    .onSubmit(submitSearch)
                    .onChange(of: searchText) { _, _ in lookup.cancel() }
                Button("Search Apple Maps", action: submitSearch)
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || lookup.state == .searching)
            }
            switch lookup.state {
            case .idle:
                if let chosenResult, draft.coordinates == PhotoLocationDraft(chosenResult.coordinates).coordinates {
                    Label(chosenResult.title, systemImage: "mappin.circle")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .searching:
                HStack {
                    ProgressView("Searching Apple Maps…").controlSize(.small)
                    Spacer()
                    Button("Stop Search", action: lookup.cancel)
                }
            case .results(let matches):
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(matches) { match in
                            Button {
                                guard let selected = lookup.choose(match.id) else { return }
                                chosenResult = selected
                                draft = PhotoLocationDraft(selected.coordinates)
                                mapSelection = UUID()
                                searchFocused = false
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(match.title)
                                    if let address = match.address {
                                        Text(address).font(.caption).foregroundStyle(.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.bordered)
                        }
                    }
                }.frame(maxHeight: showsMap ? 84 : 145)
                    .accessibilityLabel("Apple Maps results")
            case .noResults:
                Text("No places found. Try another search or enter coordinates below.")
                    .font(.caption).foregroundStyle(.secondary)
            case .unavailable:
                Text("Apple Maps lookup is unavailable. Enter coordinates below or try again.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func submitSearch() {
        guard lookup.state != .searching else { return }
        chosenResult = nil
        lookup.submit(searchText)
    }
}
