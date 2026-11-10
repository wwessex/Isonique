import IsoniqueCore
import XCTest
@testable import Isonique

final class AppPreferencesMigrationTests: XCTestCase {
    @MainActor
    func testMigrationReopensSelectedLibraryAndPreservesPresets() throws {
        let domains = preferenceDomains()
        let defaults = UserDefaults.standard
        let current = try XCTUnwrap(UserDefaults(suiteName: domains.current))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = try LibraryRepository.createEmpty(at: root)
        defer { try? FileManager.default.removeItem(at: root) }
        var library = try repository.load()
        library.projects = [Collection(name: "Migrated library")]
        try repository.save(library)
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let originalCatalogue = try Data(contentsOf: catalogue)

        let encoder = JSONEncoder()
        let imported = ImportPreset(name: "Archive", options: ImportOptions())
        let exported = ExportPreset(name: "Print", options: ExportOptions())
        let metadata = MetadataPreset(name: "Studio", values: MetadataPresetValues(caption: "Studio"))
        defaults.setPersistentDomain([
            "library.selectedRoot": repository.root.path,
            Workspace.recentLibraryKey: [repository.root.path],
            "browser.layout": BrowserPresentation.list.rawValue,
            "import.presets": try encoder.encode([imported]),
            "export.presets": try encoder.encode([exported]),
            MetadataPresetPreferences.key: try encoder.encode([metadata]),
        ], forName: domains.previous)

        AppPreferencesMigration.migrate(from: domains.previous, to: domains.current)

        let workspace = Workspace(preferences: current)
        XCTAssertEqual(workspace.repository?.root, repository.root)
        XCTAssertEqual(workspace.library.projects.map(\.name), ["Migrated library"])
        XCTAssertEqual(workspace.recentLibraryPaths, [repository.root.path])
        XCTAssertEqual(workspace.browserLayout, .list)
        XCTAssertEqual(workspace.metadataPresets, [metadata])
        let decoder = JSONDecoder()
        let importData = try XCTUnwrap(current.data(forKey: "import.presets"))
        let exportData = try XCTUnwrap(current.data(forKey: "export.presets"))
        XCTAssertEqual(try decoder.decode([ImportPreset].self, from: importData).map(\.id), [imported.id])
        XCTAssertEqual(try decoder.decode([ExportPreset].self, from: exportData).map(\.id), [exported.id])
        XCTAssertEqual(try Data(contentsOf: catalogue), originalCatalogue)
    }

    @MainActor
    func testMigrationKeepsNewValuesAndDoesNotRestoreClearedSettings() throws {
        let domains = preferenceDomains()
        let defaults = UserDefaults.standard
        let current = try XCTUnwrap(UserDefaults(suiteName: domains.current))
        defaults.setPersistentDomain([
            "library.selectedRoot": "/old/library",
            "loupe.pixelGrid": true,
            "export.presets": Data([1, 2, 3]),
        ], forName: domains.previous)
        current.set("/new/library", forKey: "library.selectedRoot")
        current.set(false, forKey: "loupe.pixelGrid")

        AppPreferencesMigration.migrate(from: domains.previous, to: domains.current)
        XCTAssertEqual(current.string(forKey: "library.selectedRoot"), "/new/library")
        XCTAssertFalse(current.bool(forKey: "loupe.pixelGrid"))
        XCTAssertEqual(current.data(forKey: "export.presets"), Data([1, 2, 3]))

        current.removeObject(forKey: "export.presets")
        AppPreferencesMigration.migrate(from: domains.previous, to: domains.current)
        XCTAssertNil(current.data(forKey: "export.presets"))
        XCTAssertEqual(defaults.persistentDomain(forName: domains.previous)?["export.presets"] as? Data, Data([1, 2, 3]))
    }

    @MainActor
    func testMigrationWithNoEarlierPreferencesKeepsFreshSettings() throws {
        let domains = preferenceDomains()
        let current = try XCTUnwrap(UserDefaults(suiteName: domains.current))
        current.set(true, forKey: "history.persist")

        AppPreferencesMigration.migrate(from: domains.previous, to: domains.current)

        XCTAssertTrue(current.bool(forKey: "history.persist"))
        XCTAssertNil(current.string(forKey: "library.selectedRoot"))
    }

    private func preferenceDomains() -> (previous: String, current: String) {
        let prefix = "IsoniqueMigrationTests.\(UUID().uuidString)"
        let previous = prefix + ".previous"
        let current = prefix + ".current"
        addTeardownBlock {
            UserDefaults.standard.removePersistentDomain(forName: previous)
            UserDefaults.standard.removePersistentDomain(forName: current)
        }
        return (previous, current)
    }
}
