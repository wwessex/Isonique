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

struct PhotoLocationEditor: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    let edit: PhotoLocationEdit
    @State private var latitude: String
    @State private var longitude: String

    init(edit: PhotoLocationEdit) {
        self.edit = edit
        let current = edit.photos.count == 1 ? edit.photos.first?.cataloguedLocation : nil
        let format = FloatingPointFormatStyle<Double>.number.grouping(.never).precision(.fractionLength(0...16))
        _latitude = State(initialValue: current?.latitude.formatted(format) ?? "")
        _longitude = State(initialValue: current?.longitude.formatted(format) ?? "")
    }

    var body: some View {
        let coordinates = GPSCoordinates(latitude: latitude, longitude: longitude)
        let count = edit.photos.count
        let changes = edit.changes(to: coordinates).count
        VStack(alignment: .leading, spacing: 14) {
            Text(edit.action.title).font(.title2.bold())
            Text(count == 1 ? (edit.photos.first?.displayName ?? "") : "\(count) selected photos")
                .foregroundStyle(.secondary)
            switch edit.action {
            case .assign:
                Grid(alignment: .leading) {
                    GridRow {
                        Text("Latitude")
                        TextField("Latitude", text: $latitude, prompt: Text("51.5"))
                            .labelsHidden().accessibilityLabel("Latitude")
                    }
                    GridRow {
                        Text("Longitude")
                        TextField("Longitude", text: $longitude, prompt: Text("-0.125"))
                            .labelsHidden().accessibilityLabel("Longitude")
                    }
                }
                Text("Enter signed decimal degrees. Latitude runs from −90 to 90 and longitude from −180 to 180.")
                    .font(.caption).foregroundStyle(.secondary)
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
                }.keyboardShortcut(.defaultAction).disabled(changes == 0)
            }
        }.padding(24).frame(width: 450)
    }
}
