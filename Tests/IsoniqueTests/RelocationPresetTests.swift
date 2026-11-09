import XCTest
import IsoniqueCore
@testable import Isonique

final class RelocationPresetTests: XCTestCase {
    func testSaveEditAndDeletePersistAcrossPreferenceInstances() throws {
        let suite = "IsoniqueRelocationTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let store = RelocationPresetStore(preferences: preferences)
        let preset = try OriginalRelocationPreset(name: "  Client Work  ",
            filenamePattern: "{catalogue}-{sequence}", subfolderPattern: "{project}/{year}")
        try store.save(preset)
        let reopened = RelocationPresetStore(preferences: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(reopened.load(), [preset])
        XCTAssertEqual(reopened.load().first?.name, "Client Work")

        let duplicate = try OriginalRelocationPreset(name: "client work", filenamePattern: "{original}", subfolderPattern: "")
        XCTAssertThrowsError(try reopened.save(duplicate))
        XCTAssertEqual(store.load(), [preset])

        let edited = try OriginalRelocationPreset(id: preset.id, name: "Client Delivery",
            filenamePattern: "Delivery-{sequence}", subfolderPattern: "")
        try reopened.save(edited)
        XCTAssertEqual(store.load(), [edited])
        try reopened.delete(edited.id)
        XCTAssertTrue(store.load().isEmpty)
    }

    func testInvalidStoredTemplateIsNotOffered() throws {
        let suite = "IsoniqueRelocationTests-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let valid = try OriginalRelocationPreset(name: "Safe", filenamePattern: "{original}", subfolderPattern: "")
        let data = try JSONEncoder().encode([valid])
        var array = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: String]])
        array.append(["id": UUID().uuidString, "name": "Invalid", "filenamePattern": "{original}", "subfolderPattern": "../escape"])
        preferences.set(try JSONSerialization.data(withJSONObject: array), forKey: RelocationPresetStore.key)
        XCTAssertEqual(RelocationPresetStore(preferences: preferences).load(), [valid])
    }
}
