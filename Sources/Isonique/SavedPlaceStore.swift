import Foundation
import IsoniqueCore

struct SavedPlace: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    let coordinates: GPSCoordinates
}

struct SavedPlaceStore {
    static let key = "location.savedPlaces"
    let preferences: UserDefaults

    func load() throws -> [SavedPlace] {
        guard let data = preferences.data(forKey: Self.key) else { return [] }
        return try JSONDecoder().decode([SavedPlace].self, from: data)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func create(named name: String, coordinates: GPSCoordinates) throws -> SavedPlace {
        var places = try load()
        let name = try validatedName(name, among: places)
        let place = SavedPlace(id: UUID(), name: name, coordinates: coordinates)
        places.append(place)
        try write(places)
        return place
    }

    func rename(_ id: UUID, to name: String) throws -> SavedPlace {
        var places = try load()
        guard let index = places.firstIndex(where: { $0.id == id }) else { throw SavedPlaceError.missing }
        places[index].name = try validatedName(name, among: places, excluding: id)
        try write(places)
        return places[index]
    }

    func remove(_ id: UUID) throws {
        try write(load().filter { $0.id != id })
    }

    private func validatedName(_ name: String, among places: [SavedPlace], excluding id: UUID? = nil) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw SavedPlaceError.emptyName }
        guard !places.contains(where: {
            $0.id != id && $0.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }) else { throw SavedPlaceError.duplicateName }
        return trimmed
    }

    private func write(_ places: [SavedPlace]) throws {
        preferences.set(try JSONEncoder().encode(places), forKey: Self.key)
    }
}

private enum SavedPlaceError: LocalizedError {
    case emptyName, duplicateName, missing

    var errorDescription: String? {
        switch self {
        case .emptyName: return String(localized: "Enter a name for the saved place.")
        case .duplicateName: return String(localized: "A saved place already uses this name.")
        case .missing: return String(localized: "This saved place was removed.")
        }
    }
}
