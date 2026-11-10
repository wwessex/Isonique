import Foundation
import IsoniqueCore

enum MetadataPresetPreferences {
    static let key = "metadata.presets"

    static func load(from preferences: UserDefaults) -> [MetadataPreset] {
        guard let data = preferences.data(forKey: key),
              let presets = try? JSONDecoder().decode([MetadataPreset].self, from: data) else { return [] }
        return presets
    }
}

extension Workspace {
    @discardableResult
    func saveMetadataPreset(named name: String, values: MetadataPresetValues) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, values.hasChanges else { return false }
        var presets = MetadataPresetPreferences.load(from: preferences)
        guard !presets.contains(where: { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame })
        else { return false }
        presets.append(MetadataPreset(name: clean, values: values))
        presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return storeMetadataPresets(presets)
    }

    func deleteMetadataPreset(_ id: UUID) {
        _ = storeMetadataPresets(MetadataPresetPreferences.load(from: preferences).filter { $0.id != id })
    }

    private func storeMetadataPresets(_ presets: [MetadataPreset]) -> Bool {
        guard let data = try? JSONEncoder().encode(presets) else { return false }
        preferences.set(data, forKey: MetadataPresetPreferences.key)
        metadataPresets = presets
        return true
    }
}
