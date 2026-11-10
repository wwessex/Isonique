import IsoniqueCore
import XCTest
@testable import Isonique

final class IPTCSearchTests: XCTestCase {
    @MainActor
    func testQuickAndAdvancedSearchAndSmartAlbumFollowEditsAfterReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueIPTCSearch-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        var first = Photo(filename: "a.jpg", originalName: "A.jpg", projectID: nil, width: 20, height: 20,
                          camera: "", captureDate: "", sha256: "A")
        first.iptc = IPTCMetadata(title: "Harbour", creators: ["Alex Ng", "Jo Weiß"], copyright: "Studio", credit: "News Desk")
        let second = Photo(filename: "b.jpg", originalName: "B.jpg", projectID: nil, width: 20, height: 20,
                           camera: "", captureDate: "", sha256: "B")
        var draft = workspace.library
        draft.photos = [first, second]
        XCTAssertTrue(workspace.commit(draft))
        for term in ["Harbour", "Jo Weiß", "Studio", "News Desk"] {
            workspace.search = term
            XCTAssertEqual(workspace.photos.map(\.id), [first.id])
        }

        workspace.search = ""
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .iptcCreator, comparison: .equals, value: "Alex Ng")]
        workspace.advancedSearch = query
        XCTAssertEqual(workspace.photos.map(\.id), [first.id])
        var rule = SmartAlbumRule()
        rule.query = query
        XCTAssertTrue(workspace.saveSmartAlbum(name: "Alex", rule: rule))
        let scope = workspace.scope
        workspace.selection = first.id
        workspace.edit { $0.iptc?.creators = [] }
        XCTAssertTrue(workspace.photos.isEmpty)

        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        reopened.scope = scope
        XCTAssertTrue(reopened.photos.isEmpty)
        reopened.undoEdit()
        XCTAssertEqual(reopened.photos.map(\.id), [first.id])
        reopened.redoEdit()
        XCTAssertTrue(reopened.photos.isEmpty)
    }
}
