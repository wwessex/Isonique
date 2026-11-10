import IsoniqueCore
import SwiftUI

struct SavedPlacesMenu: View {
    @EnvironmentObject private var model: Workspace
    let coordinates: GPSCoordinates?
    let suggestedName: String?
    let onSelect: (GPSCoordinates) -> Void

    @State private var places: [SavedPlace] = []
    @State private var selectedID: UUID?
    @State private var nameEdit: NameEdit?
    @State private var removal: SavedPlace?
    @State private var error: String?

    private var store: SavedPlaceStore { SavedPlaceStore(preferences: model.preferences) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Menu("Saved Places") {
                    if places.isEmpty { Text("No saved places") }
                    ForEach(places) { place in
                        Button(place.name) {
                            selectedID = place.id
                            onSelect(place.coordinates)
                        }
                    }
                    Divider()
                    Button("Save Current Coordinates…") {
                        if let coordinates { nameEdit = .create(coordinates, suggestedName ?? "") }
                    }.disabled(coordinates == nil)
                    Menu("Rename Saved Place") {
                        ForEach(places) { place in
                            Button(place.name) { nameEdit = .rename(place) }
                        }
                    }.disabled(places.isEmpty)
                    Menu("Remove Saved Place") {
                        ForEach(places) { place in
                            Button(place.name) { removal = place }
                        }
                    }.disabled(places.isEmpty)
                }.fixedSize()
                if let selected = places.first(where: { $0.id == selectedID }),
                   PhotoLocationDraft(selected.coordinates).coordinates == coordinates {
                    Text(selected.name).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear(perform: reload)
        .sheet(item: $nameEdit) { edit in
            SavedPlaceNameEditor(title: edit.title, initialName: edit.name) { name in
                switch edit {
                case .create(let coordinates, _):
                    let place = try store.create(named: name, coordinates: coordinates)
                    selectedID = place.id
                case .rename(let place):
                    _ = try store.rename(place.id, to: name)
                }
                reload()
            }
        }
        .alert("Remove Saved Place?", isPresented: Binding(get: { removal != nil }, set: {
            if !$0 { removal = nil }
        }), presenting: removal) { place in
            Button("Remove Place", role: .destructive) {
                do {
                    try store.remove(place.id)
                    reload()
                } catch {
                    self.error = String(localized: "Could not remove the saved place.")
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { place in
            Text(place.name)
        }
    }

    private func reload() {
        do {
            places = try store.load()
            error = nil
        } catch {
            self.error = String(localized: "Could not load saved places.")
        }
    }

    private enum NameEdit: Identifiable {
        case create(GPSCoordinates, String)
        case rename(SavedPlace)

        var id: UUID? {
            if case .rename(let place) = self { return place.id }
            return nil
        }

        var title: LocalizedStringKey {
            switch self {
            case .create: return "Save Place"
            case .rename: return "Rename Place"
            }
        }

        var name: String {
            switch self {
            case .create(_, let name): return name
            case .rename(let place): return place.name
            }
        }
    }
}

private struct SavedPlaceNameEditor: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    let save: (String) throws -> Void
    @State private var name: String
    @State private var error: String?

    init(title: LocalizedStringKey, initialName: String, save: @escaping (String) throws -> Void) {
        self.title = title
        self.save = save
        _name = State(initialValue: initialName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2.bold())
            TextField("Place name", text: $name)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(title) {
                    do {
                        try save(name)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                    }
                }.keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 360)
    }
}
