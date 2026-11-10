import Foundation
import IsoniqueCore

enum MetadataViewField: String, CaseIterable, Codable, Identifiable {
    case name, dimensions, camera, captured, imported, rating, flag, colorLabel
    case caption, keywords, keywordPaths, title, creator, copyright, credit
    case shutterSpeed, aperture, iso, focalLength, lens, latitude, longitude, originalStorage, linkedOriginal

    var id: Self { self }

    var label: String {
        switch self {
        case .name: return String(localized: "Photo name")
        case .dimensions: return String(localized: "Dimensions")
        case .camera: return String(localized: "Camera")
        case .captured: return String(localized: "Captured")
        case .imported: return String(localized: "Imported")
        case .rating: return String(localized: "Rating")
        case .flag: return String(localized: "Flagged")
        case .colorLabel: return String(localized: "Color label")
        case .caption: return String(localized: "Caption")
        case .keywords: return String(localized: "Keywords")
        case .keywordPaths: return String(localized: "Vocabulary Keywords")
        case .title: return IPTCField.title.title
        case .creator: return IPTCField.creator.title
        case .copyright: return IPTCField.copyright.title
        case .credit: return IPTCField.credit.title
        case .shutterSpeed: return String(localized: "Shutter speed")
        case .aperture: return String(localized: "Aperture")
        case .iso: return String(localized: "ISO")
        case .focalLength: return String(localized: "Focal length")
        case .lens: return String(localized: "Lens")
        case .latitude: return String(localized: "Latitude")
        case .longitude: return String(localized: "Longitude")
        case .originalStorage: return String(localized: "Original storage")
        case .linkedOriginal: return String(localized: "Linked RAW + JPEG")
        }
    }

    var iptcField: IPTCField? {
        switch self {
        case .title: return .title
        case .creator: return .creator
        case .copyright: return .copyright
        case .credit: return .credit
        default: return nil
        }
    }

    var isGPS: Bool { self == .latitude || self == .longitude }

    var isEXIF: Bool {
        switch self {
        case .shutterSpeed, .aperture, .iso, .focalLength, .lens: return true
        default: return false
        }
    }
}

enum BuiltInMetadataView: String, CaseIterable, Codable, Identifiable {
    case general, exif, gps, iptc, captionAndKeywords
    var id: Self { self }

    var name: String {
        switch self {
        case .general: return String(localized: "General")
        case .exif: return String(localized: "EXIF Info")
        case .gps: return String(localized: "GPS")
        case .iptc: return String(localized: "IPTC Core")
        case .captionAndKeywords: return String(localized: "Caption & Keywords")
        }
    }

    var fields: [MetadataViewField] {
        switch self {
        case .general:
            return [.dimensions, .camera, .captured, .imported, .shutterSpeed, .aperture, .iso, .focalLength, .lens,
                    .rating, .flag, .linkedOriginal, .colorLabel, .caption, .keywords, .keywordPaths,
                    .title, .creator, .copyright, .credit, .originalStorage]
        case .exif: return [.camera, .captured, .shutterSpeed, .aperture, .iso, .focalLength, .lens]
        case .gps: return [.latitude, .longitude]
        case .iptc: return [.title, .creator, .copyright, .credit]
        case .captionAndKeywords: return [.caption, .keywords, .keywordPaths]
        }
    }
}

enum MetadataViewSelection: Hashable, Codable {
    case builtIn(BuiltInMetadataView)
    case custom(UUID)
}

struct CustomMetadataView: Codable, Hashable, Identifiable {
    let id: UUID
    let name: String
    let fields: [MetadataViewField]

    init(id: UUID = UUID(), name: String, fields: [MetadataViewField]) {
        self.id = id
        self.name = name
        self.fields = fields
    }

    private enum CodingKeys: String, CodingKey { case id, name, fields }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Preserve the order of supported fields when reading preferences from a newer build.
        fields = try container.decode([String].self, forKey: .fields).compactMap(MetadataViewField.init(rawValue:))
    }
}

struct MetadataViewPreferences: Codable, Equatable {
    static let key = "metadata.infoViews"
    private(set) var customViews: [CustomMetadataView] = []
    private(set) var selection: MetadataViewSelection = .builtIn(.general)

    var selectedCustomView: CustomMetadataView? {
        guard case .custom(let id) = selection else { return nil }
        return customViews.first { $0.id == id }
    }

    static func load(from preferences: UserDefaults) -> Self {
        guard let data = preferences.data(forKey: key),
              let saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var result = Self()
        for view in saved.customViews where !result.customViews.contains(where: { $0.id == view.id }) {
            _ = result.save(view, checkingBuiltInName: false)
        }
        result.select(saved.selection)
        return result
    }

    mutating func select(_ view: MetadataViewSelection) {
        if case .custom(let id) = view, !customViews.contains(where: { $0.id == id }) {
            selection = .builtIn(.general)
        } else {
            selection = view
        }
    }

    func accepts(_ view: CustomMetadataView, checkingBuiltInName: Bool = true) -> Bool {
        let name = view.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !view.fields.isEmpty else { return false }
        let usesBuiltInName = checkingBuiltInName && BuiltInMetadataView.allCases.contains {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        return !usesBuiltInName && !customViews.contains { $0.id != view.id && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
    }

    mutating func save(_ view: CustomMetadataView, checkingBuiltInName: Bool = true) -> Bool {
        guard accepts(view, checkingBuiltInName: checkingBuiltInName) else { return false }
        var seen: Set<MetadataViewField> = []
        let normalized = CustomMetadataView(id: view.id, name: view.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                            fields: view.fields.filter { seen.insert($0).inserted })
        if let index = customViews.firstIndex(where: { $0.id == view.id }) {
            customViews[index] = normalized
        } else {
            customViews.append(normalized)
        }
        return true
    }

    mutating func delete(_ id: UUID) {
        customViews.removeAll { $0.id == id }
        select(selection)
    }
}

extension Workspace {
    func selectMetadataView(_ selection: MetadataViewSelection) {
        var views = MetadataViewPreferences.load(from: preferences)
        views.select(selection)
        storeMetadataViews(views)
    }

    @discardableResult
    func saveMetadataView(_ view: CustomMetadataView) -> Bool {
        var views = MetadataViewPreferences.load(from: preferences)
        guard views.save(view) else { return false }
        views.select(.custom(view.id))
        storeMetadataViews(views)
        return true
    }

    func deleteMetadataView(_ id: UUID) {
        var views = MetadataViewPreferences.load(from: preferences)
        views.delete(id)
        storeMetadataViews(views)
    }

    private func storeMetadataViews(_ views: MetadataViewPreferences) {
        guard let data = try? JSONEncoder().encode(views) else { return }
        preferences.set(data, forKey: MetadataViewPreferences.key)
        metadataViews = views
    }
}
