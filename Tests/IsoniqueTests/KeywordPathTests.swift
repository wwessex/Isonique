import IsoniqueCore
import XCTest
@testable import Isonique

final class KeywordPathTests: XCTestCase {
    @MainActor
    func testAssignmentKeepsBranchesAndLegacyKeywordsSeparateAfterReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueKeywordPaths-\(UUID())")
        let suite = root.lastPathComponent
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let vocabulary = try KeywordVocabulary(text: "Places\n\tLondon\nPeople\n\tLondon\n")
        try workspace.updateKeywordVocabulary { $0 = vocabulary }
        let placeID = try XCTUnwrap(vocabulary.roots.first?.children.first?.id)
        let place = try XCTUnwrap(vocabulary.path(to: placeID))
        let person = try XCTUnwrap(vocabulary.paths.last)
        var legacy = photo("Legacy")
        legacy.keywords = "London, Archive"
        let first = photo("First")
        let second = photo("Second")
        var draft = workspace.library
        draft.photos = [first, second, legacy]
        XCTAssertTrue(workspace.commit(draft))
        XCTAssertLessThan(workspace.library.version, 10)

        workspace.selection = first.id
        XCTAssertTrue(workspace.changeKeywordPath(place, adding: true))
        XCTAssertFalse(workspace.changeKeywordPath(try XCTUnwrap(KeywordPath(["PLACES", "london"])), adding: true))
        workspace.selection = second.id
        XCTAssertTrue(workspace.changeKeywordPath(person, adding: true))
        workspace.selection = first.id
        XCTAssertTrue(workspace.changeKeywordPath(person, adding: true))
        XCTAssertTrue(workspace.addKeywords("Archive"))
        XCTAssertTrue(workspace.removeKeywords("Archive"))
        XCTAssertEqual(workspace.library.photos[0].keywordPaths, [place, person])
        XCTAssertEqual(workspace.library.photos[2], legacy)

        workspace.undoEdit()
        XCTAssertEqual(workspace.library.photos[0].keywords, "Archive")
        workspace.redoEdit()
        XCTAssertTrue(workspace.changeKeywordPath(person, adding: false))
        workspace.undoEdit()
        XCTAssertEqual(workspace.library.photos[0].keywordPaths, [place, person])
        workspace.redoEdit()
        XCTAssertEqual(workspace.library.photos[0].keywordPaths, [place])

        let placesID = try XCTUnwrap(vocabulary.roots.first?.id)
        try workspace.updateKeywordVocabulary { try $0.delete(placesID) }
        XCTAssertNil(workspace.keywordVocabulary.path(to: placeID))
        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        XCTAssertEqual(reopened.library.version, 10)
        XCTAssertEqual(reopened.library.photos.map(\.keywordPaths), [[place], [person], nil])
        XCTAssertTrue(reopened.keywordPathChoices.contains(place))
        XCTAssertTrue(reopened.keywordPathChoices.contains(try XCTUnwrap(KeywordPath(["Places"]))))
        reopened.findPhotos(with: place)
        XCTAssertEqual(reopened.photos.map(\.id), [first.id])
        reopened.findPhotos(with: person)
        XCTAssertEqual(reopened.photos.map(\.id), [second.id])
        reopened.undoEdit()
        XCTAssertEqual(Set(reopened.photos.map(\.id)), [first.id, second.id])
        reopened.redoEdit()
        XCTAssertEqual(reopened.photos.map(\.id), [second.id])
    }

    func testSearchMatchesExactPathsAndBranchesAndStillFindsFlatTerms() throws {
        var first = photo("First")
        first.keywordPaths = [try XCTUnwrap(KeywordPath(["Places", "London"]))]
        var second = photo("Second")
        second.keywordPaths = [try XCTUnwrap(KeywordPath(["People", "London"]))]
        var legacy = photo("Legacy")
        legacy.keywords = "London, Archive"

        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .keyword, comparison: .equals, value: "London")]
        XCTAssertEqual([first, second, legacy].filter { query.includes($0) }, [first, second, legacy])
        let branch = try XCTUnwrap(KeywordPath(["places"]))
        query.criteria = [PhotoQueryCriterion(field: .keywordPath, comparison: .equals, keywordPath: branch)]
        XCTAssertTrue([first, second, legacy].filter { query.includes($0) }.isEmpty)
        query.criteria[0].comparison = .inBranch
        XCTAssertEqual([first, second, legacy].filter { query.includes($0) }, [first])
        query.criteria[0].comparison = .differs
        query.criteria[0].keywordPath = first.keywordPaths?.first
        XCTAssertEqual([first, second, legacy].filter { query.includes($0) }, [second, legacy])
        XCTAssertEqual(try JSONDecoder().decode(PhotoQuery.self, from: JSONEncoder().encode(query)), query)
    }

    @MainActor
    func testSavingPathRuleUpgradesCatalogueWithoutAssignments() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueKeywordRule-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        var query = PhotoQuery()
        let path = try XCTUnwrap(KeywordPath(["Places", "London"]))
        query.criteria = [PhotoQueryCriterion(field: .keywordPath, comparison: .equals, keywordPath: path)]
        var rule = SmartAlbumRule()
        rule.query = query
        XCTAssertTrue(workspace.saveSmartAlbum(name: "Places in London", rule: rule))
        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        XCTAssertEqual(reopened.library.version, 10)
        XCTAssertEqual(reopened.library.albums.first?.rule?.query, query)
    }

    private func photo(_ name: String) -> Photo {
        Photo(filename: name + ".jpg", originalName: name + ".jpg", projectID: nil,
              width: 20, height: 16, camera: "", captureDate: "", sha256: name)
    }
}
