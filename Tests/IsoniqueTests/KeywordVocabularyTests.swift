import IsoniqueCore
import XCTest
@testable import Isonique

final class KeywordVocabularyTests: XCTestCase {
    func testDuplicateBranchesMergeWithFirstSpellingAndOrder() throws {
        var vocabulary = try KeywordVocabulary(text: "\u{FEFF}Places\r\n\tCafé\r\n\t\tDetails\r\n\nPeople\r\n\tCafé\r\n")
        let originalPlaces = try XCTUnwrap(vocabulary.roots.first)
        let incoming = try KeywordVocabulary(text: "places\n\tCAFE\u{301}\n\t\tInteriors\nPLACES\n\tYork\n\tYORK\n")
        XCTAssertEqual(vocabulary.merge(incoming), 2)
        XCTAssertEqual(vocabulary.merge(incoming), 0)
        XCTAssertEqual(vocabulary.roots.first?.id, originalPlaces.id)
        XCTAssertEqual(vocabulary.roots.first?.children.first?.id, originalPlaces.children.first?.id)
        XCTAssertEqual(vocabulary.text, "Places\n\tCafé\n\t\tDetails\n\t\tInteriors\n\tYork\nPeople\n\tCafé\n")
        XCTAssertEqual(try KeywordVocabulary(text: vocabulary.text).text, vocabulary.text)
    }

    func testEditingValidatesSiblingNamesAndKeepsChildrenOnRename() throws {
        var vocabulary = KeywordVocabulary()
        let places = try vocabulary.add("Places")
        let child = try vocabulary.add("London", under: places)
        let people = try vocabulary.add("People")
        try vocabulary.add("London", under: people)
        XCTAssertThrowsError(try vocabulary.add("london", under: places))
        XCTAssertThrowsError(try vocabulary.rename(places, to: "People"))
        XCTAssertThrowsError(try vocabulary.add("One, Two"))
        try vocabulary.rename(places, to: " Travel ")
        XCTAssertEqual(vocabulary.entry(places)?.name, "Travel")
        XCTAssertEqual(vocabulary.entry(places)?.children.first?.id, child)
        try vocabulary.delete(places)
        XCTAssertNil(vocabulary.entry(child))
        XCTAssertEqual(vocabulary.text, "People\n\tLondon\n")
    }

    @MainActor
    func testFileRoundTripPersistsAndRejectsMalformedInputBeforeSaving() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueVocabulary-\(UUID())")
        let suite = root.lastPathComponent
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let freshPreferences = try XCTUnwrap(UserDefaults(suiteName: suite + "-import"))
        defer {
            preferences.removePersistentDomain(forName: suite)
            freshPreferences.removePersistentDomain(forName: suite + "-import")
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = Workspace(libraryRoot: root.appendingPathComponent("First"), preferences: preferences)
        let source = root.appendingPathComponent("Keywords.txt")
        let exported = root.appendingPathComponent("Exported.txt")
        try "Locations\n\tTokyo\n\tZürich\n".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertEqual(try workspace.importKeywordVocabulary(from: source), 3)
        XCTAssertEqual(try workspace.importKeywordVocabulary(from: source), 0)
        let saved = workspace.keywordVocabulary

        try "New\n\t\tBroken indentation\n".write(to: source, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try workspace.importKeywordVocabulary(from: source)) {
            XCTAssertEqual($0.localizedDescription, "Invalid keyword or tab indentation on line 2.")
        }
        try Data([0xFF]).write(to: source)
        XCTAssertThrowsError(try workspace.importKeywordVocabulary(from: source))
        XCTAssertEqual(workspace.keywordVocabulary, saved)

        let reopened = Workspace(libraryRoot: root.appendingPathComponent("Second"), preferences: preferences)
        XCTAssertEqual(reopened.keywordVocabulary, saved)
        try reopened.exportKeywordVocabulary(to: exported)
        let fresh = Workspace(libraryRoot: root.appendingPathComponent("Third"), preferences: freshPreferences)
        XCTAssertEqual(try fresh.importKeywordVocabulary(from: exported), 3)
        XCTAssertEqual(fresh.keywordVocabulary.text, saved.text)
    }
}
