import IsoniqueCore
import XCTest
@testable import Isonique

final class KeywordGroupTests: XCTestCase {
    @MainActor
    func testGroupsAndControlsPersistAcrossLibrariesAndSupportEditingAndDeleting() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        let first = Workspace(libraryRoot: root.appendingPathComponent("First"), preferences: preferences)
        XCTAssertFalse(first.showKeywordControls)
        XCTAssertNil(first.keywordGroups.active)
        XCTAssertThrowsError(try KeywordGroup(name: "  ", keywordText: "Snow"))
        XCTAssertThrowsError(try KeywordGroup(name: "Travel", keywordText: " , "))

        let coast = try KeywordGroup(name: "  Coast ", keywordText: "Café, CAFE\u{301}, surf, SURF, Blue Hour")
        let street = try KeywordGroup(name: "Street", keywordText: "City, Night")
        try first.saveKeywordGroup(coast)
        try first.saveKeywordGroup(street)
        XCTAssertTrue(first.showKeywordControls)
        XCTAssertEqual(coast.keywords, ["Café", "surf", "Blue Hour"])
        XCTAssertEqual(first.keywordGroups.active, street)
        let duplicate = try KeywordGroup(name: "COAST", keywordText: "Other")
        XCTAssertThrowsError(try first.saveKeywordGroup(duplicate))
        XCTAssertEqual(first.keywordGroups.groups, [coast, street])

        first.selectKeywordGroup(coast.id)
        let second = Workspace(libraryRoot: root.appendingPathComponent("Second"), preferences: preferences)
        XCTAssertEqual(second.keywordGroups.groups, [coast, street])
        XCTAssertEqual(second.keywordGroups.active, coast)
        XCTAssertTrue(second.showKeywordControls)
        let edited = try KeywordGroup(id: coast.id, name: "Coastal", keywordText: "Blue Hour, surf")
        try second.saveKeywordGroup(edited)
        second.showKeywordControls = false

        let reopened = Workspace(libraryRoot: root.appendingPathComponent("First"), preferences: preferences)
        XCTAssertEqual(reopened.keywordGroups.groups, [edited, street])
        XCTAssertEqual(reopened.keywordGroups.active, edited)
        XCTAssertFalse(reopened.showKeywordControls)
        try reopened.deleteKeywordGroup(edited.id)
        XCTAssertEqual(reopened.keywordGroups.active, street)
        try reopened.deleteKeywordGroup(street.id)
        XCTAssertTrue(KeywordGroupPreferences.load(from: preferences).groups.isEmpty)
        XCTAssertNil(KeywordGroupPreferences.load(from: preferences).active)
    }

    @MainActor
    func testApplyGroupUsesVisibleSelectionAndOnePersistentUndoStep() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        preferences.set(true, forKey: "history.persist")
        let libraryRoot = root.appendingPathComponent("Library")
        let workspace = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        let group = try KeywordGroup(name: "Coast", keywordText: "COAST, Fog")
        try workspace.saveKeywordGroup(group)

        let project = Collection(name: "Current shoot")
        let first = photo("First", keywords: "Coast, Sunrise", projectID: project.id)
        let second = photo("Second", keywords: "", projectID: project.id)
        let deselected = photo("Unselected", keywords: "Leave alone", projectID: project.id)
        let hidden = photo("Hidden", keywords: "Out of scope")
        var trashed = photo("Trashed", keywords: "Keep in Trash", projectID: project.id)
        trashed.trashedAt = Date()
        var draft = workspace.library
        draft.projects = [project]
        draft.photos = [first, second, deselected, hidden, trashed]
        let sibling = try XCTUnwrap(draft.createVersion(of: first.id, from: .current))
        XCTAssertTrue(workspace.commit(draft))

        workspace.scope = "project:\(project.id)"
        workspace.batchMode = true
        XCTAssertFalse(workspace.addKeywords(group.keywordText))
        workspace.batchSelection = [first.id, second.id, hidden.id, trashed.id]
        XCTAssertTrue(workspace.addKeywords(group.keywordText))
        XCTAssertEqual(workspace.library.photos.map(\.keywords),
                       ["Coast, Sunrise, Fog", "COAST, Fog", deselected.keywords, hidden.keywords, trashed.keywords, sibling.keywords])
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.library.version, 9)

        let catalogue = libraryRoot.appendingPathComponent("catalog.json")
        let saved = try Data(contentsOf: catalogue)
        XCTAssertFalse(workspace.addKeywords(group.keywordText))
        XCTAssertEqual(try Data(contentsOf: catalogue), saved)
        XCTAssertEqual(workspace.history.undo.count, 1)
        try workspace.deleteKeywordGroup(group.id)
        XCTAssertEqual(try Data(contentsOf: catalogue), saved)

        let reopened = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        XCTAssertEqual(reopened.library.photos, workspace.library.photos)
        XCTAssertNil(reopened.keywordGroups.active)
        reopened.undoEdit()
        XCTAssertEqual(reopened.library.photos, draft.photos)
        reopened.redoEdit()
        XCTAssertEqual(reopened.library.photos, workspace.library.photos)

        reopened.scope = "trash"
        reopened.selection = trashed.id
        XCTAssertFalse(reopened.addKeywords("Forbidden"))
        XCTAssertEqual(reopened.library.photos, workspace.library.photos)
    }

    @MainActor
    func testIndividualKeywordAppliesToSinglePhotoAndLeavesOtherMetadataAlone() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        let workspace = Workspace(libraryRoot: root.appendingPathComponent("Library"), preferences: preferences)
        let first = photo("First", keywords: "Existing")
        let second = photo("Second", keywords: "Unselected")
        var draft = workspace.library
        draft.photos = [first, second]
        XCTAssertTrue(workspace.commit(draft))

        let group = try KeywordGroup(name: "Light", keywordText: "Dawn, Dusk")
        try workspace.saveKeywordGroup(group)
        workspace.selection = first.id
        XCTAssertTrue(workspace.addKeywords(group.keywords[1]))
        var expected = first
        expected.keywords = "Existing, Dusk"
        XCTAssertEqual(workspace.library.photos, [expected, second])
        workspace.undoEdit()
        XCTAssertEqual(workspace.library.photos, [first, second])
        workspace.redoEdit()
        XCTAssertEqual(workspace.library.photos, [expected, second])
    }

    @MainActor
    func testQuickRemovalChangesOnlyVisibleSelectionAndUndoesAsOneEdit() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let project = Collection(name: "Current shoot")
        let first = photo("First", keywords: "Coast, CAFE\u{301}, café, blue hour", projectID: project.id)
        let second = photo("Second", keywords: "CAFÉ", projectID: project.id)
        let unselected = photo("Unselected", keywords: "CAFÉ", projectID: project.id)
        let hidden = photo("Hidden", keywords: "CAFÉ")
        var draft = workspace.library
        draft.projects = [project]
        draft.photos = [first, second, unselected, hidden]
        XCTAssertTrue(workspace.commit(draft))

        workspace.scope = "project:\(project.id)"
        workspace.batchMode = true
        workspace.batchSelection = [first.id, second.id, hidden.id]
        XCTAssertTrue(workspace.removeKeywords("Café"))
        XCTAssertEqual(workspace.library.photos.map(\.keywords), ["Coast, blue hour", "", "CAFÉ", "CAFÉ"])
        XCTAssertEqual(workspace.library.photos.map(\.caption), draft.photos.map(\.caption))
        XCTAssertFalse(workspace.removeKeywords("Café"))
        XCTAssertEqual(workspace.history.undo.count, 1)

        let removed = workspace.library.photos
        workspace.undoEdit()
        XCTAssertEqual(workspace.library.photos, draft.photos)
        workspace.redoEdit()
        XCTAssertEqual(workspace.library.photos, removed)
    }

    @MainActor
    func testKeywordShortcutUsesActiveGroupAndRequiresAnEligibleSelection() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        var draft = workspace.library
        let first = photo("First", keywords: "Keep")
        let second = photo("Second", keywords: "")
        draft.photos = [first, second]
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = first.id

        XCTAssertEqual(workspace.keywordShortcut("1", modifiers: .option), .ignored)
        let light = try KeywordGroup(name: "Light", keywordText: "Dawn, Dusk")
        let places = try KeywordGroup(name: "Places", keywordText: "Coast, Hills")
        try workspace.saveKeywordGroup(light)
        try workspace.saveKeywordGroup(places)
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: []), .ignored)
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: [.command, .option]), .ignored)
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: [.option, .numericPad]), .ignored)
        XCTAssertEqual(workspace.keywordShortcut("3", modifiers: .option), .ignored)
        workspace.showKeywordControls = false
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: .option), .ignored)
        workspace.showKeywordControls = true
        workspace.batchMode = true
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: .option), .ignored)

        workspace.batchSelection = [first.id, second.id]
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: .option), .handled)
        XCTAssertEqual(workspace.library.photos.map(\.keywords), ["Keep, Hills", "Hills"])
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: [.option, .shift]), .handled)
        XCTAssertEqual(workspace.library.photos, draft.photos)
        workspace.selectKeywordGroup(light.id)
        XCTAssertEqual(workspace.keywordShortcut("2", modifiers: .option), .handled)
        XCTAssertEqual(workspace.library.photos.map(\.keywords), ["Keep, Dusk", "Dusk"])
    }

    private func photo(_ name: String, keywords: String, projectID: UUID? = nil) -> Photo {
        var photo = Photo(filename: name + ".jpg", originalName: name + ".jpg", projectID: projectID,
                          width: 20, height: 16, camera: "", captureDate: "", sha256: name)
        photo.caption = "Caption for \(name)"
        photo.keywords = keywords
        return photo
    }

    private func fixture() throws -> (URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueKeywords-\(UUID())")
        return (root, try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent)))
    }

    private func cleanUp(_ root: URL, _ preferences: UserDefaults) {
        preferences.removePersistentDomain(forName: root.lastPathComponent)
        try? FileManager.default.removeItem(at: root)
    }
}
