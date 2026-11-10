import IsoniqueCore
import XCTest
@testable import Isonique

final class BatchMetadataTests: XCTestCase {
    func testPreviewSupportsIndependentFieldsAppendReplaceAndClearing() throws {
        var first = photo("First", caption: "Old caption", keywords: " Coast , Café, Coast ")
        let second = photo("Second", caption: "", keywords: "coast,  Blue Hour")
        let review = BatchMetadataReview(photos: [first, second])
        let appended = review.preview(caption: nil, keywordMode: .append,
                                      keywords: " COAST, CAFE\u{301}, coast, fog, FOG, , cafe ")
        XCTAssertEqual(appended.rows.map(\.id), [first.id, second.id])
        XCTAssertEqual(appended.rows.map(\.before.keywords), [first.keywords, second.keywords])
        XCTAssertEqual(appended.rows.map(\.after.keywords),
                       ["Coast, Café, Coast, fog, cafe", "coast, Blue Hour, CAFE\u{301}, fog, cafe"])
        XCTAssertTrue(appended.rows.allSatisfy { $0.after.caption == nil })
        XCTAssertTrue(review.preview(caption: nil, keywordMode: .append, keywords: "COAST,, ").rows.isEmpty)
        XCTAssertTrue(review.preview(caption: nil, keywordMode: .unchanged, keywords: "Ignored").rows.isEmpty)

        let replaced = review.preview(caption: "New\ncaption", keywordMode: .replace, keywords: " fog , FOG, blue hour")
        XCTAssertEqual(replaced.rows.map(\.after.keywords), ["fog, blue hour", "fog, blue hour"])
        XCTAssertEqual(replaced.rows.map(\.after.caption), ["New\ncaption", "New\ncaption"])
        let cleared = review.preview(caption: "", keywordMode: .replace, keywords: " , ")
        XCTAssertEqual(cleared.rows.map(\.after.caption), ["", nil])
        XCTAssertEqual(cleared.rows.map(\.after.keywords), ["", ""])

        var library = Library()
        first.rating = 4
        library.photos = [first, second]
        let inverse = try XCTUnwrap(review.apply(appended, to: &library))
        XCTAssertEqual(inverse, appended.rows.map(\.before))
        XCTAssertEqual(library.photos.map(\.caption), [first.caption, second.caption])
        XCTAssertEqual(library.photos[0].rating, 4)
    }

    @MainActor
    func testBatchSelectionSmartAlbumAndOneStepUndoRedoSurviveReopen() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let project = Collection(name: "Shoot")
        let first = photo("First", caption: "First caption", keywords: "Studio", projectID: project.id)
        let second = photo("Second", caption: "Second caption", keywords: "Location", projectID: project.id)
        let deselected = photo("Deselected", caption: "Leave alone", keywords: "Day", projectID: project.id)
        let hidden = photo("Hidden", caption: "Other project", keywords: "Rain")
        var trashed = photo("Trashed", caption: "Keep in Trash", keywords: "Archive", projectID: project.id)
        trashed.trashedAt = Date()
        var draft = workspace.library
        draft.projects = [project]
        draft.photos = [first, second, deselected, hidden, trashed]
        let sibling = try XCTUnwrap(draft.createVersion(of: first.id, from: .current))
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .keyword, comparison: .equals, value: "Reviewed")]
        var rule = SmartAlbumRule(minimumRating: 0, text: "")
        rule.query = query
        var album = Collection(name: "Reviewed")
        album.rule = rule
        draft.albums = [album]
        XCTAssertTrue(workspace.commit(draft))

        workspace.scope = "project:\(project.id)"
        workspace.sort = .name
        workspace.selection = first.id
        workspace.batchMode = true
        XCTAssertFalse(workspace.canOpenBatchMetadata)
        workspace.batchSelection = [first.id, second.id, hidden.id, trashed.id]
        workspace.openBatchMetadata()
        let review = try XCTUnwrap(workspace.batchMetadataReview)
        XCTAssertEqual(review.photoCount, 2)
        let before = try Data(contentsOf: root.appendingPathComponent("catalog.json"))
        let preview = review.preview(caption: "Approved", keywordMode: .append, keywords: "reviewed")
        XCTAssertEqual(preview.rows.map(\.id), [first.id, second.id])
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("catalog.json")), before)
        workspace.batchSelection = [deselected.id]
        XCTAssertTrue(workspace.applyBatchMetadata(preview, for: review))
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.library.version, 9)
        XCTAssertEqual(workspace.library.photos.filter { ![first.id, second.id].contains($0.id) },
                       [deselected, hidden, trashed, sibling])

        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        reopened.scope = "album:\(album.id)"
        reopened.sort = .name
        XCTAssertEqual(reopened.photos.map(\.caption), ["Approved", "Approved"])
        XCTAssertEqual(reopened.photos.map(\.keywords), ["Studio, reviewed", "Location, reviewed"])
        reopened.undoEdit()
        XCTAssertTrue(reopened.photos.isEmpty)
        XCTAssertEqual(reopened.library.photos, draft.photos)
        reopened.redoEdit()
        XCTAssertEqual(reopened.photos.map(\.id), [first.id, second.id])
        XCTAssertEqual(try reopened.repository?.load().photos, workspace.library.photos)

        reopened.scope = "trash"
        XCTAssertFalse(reopened.canOpenBatchMetadata)
    }

    @MainActor
    func testChangedTargetsRejectPreviewAndHistoryIsOptional() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let first = photo("First", caption: "Unchanged", keywords: "Travel")
        let second = photo("Second", caption: "Before", keywords: "Summer")
        var draft = workspace.library
        draft.photos = [first, second]
        XCTAssertTrue(workspace.commit(draft))
        workspace.batchMode = true
        workspace.batchSelection = [first.id, second.id]
        workspace.openBatchMetadata()
        let review = try XCTUnwrap(workspace.batchMetadataReview)
        let preview = review.preview(caption: "Batch", keywordMode: .replace, keywords: "Beach")
        workspace.editBatch { $0.keywords += ", Edited" }
        let updated = workspace.library.photos
        let history = workspace.history.undo
        XCTAssertFalse(workspace.applyBatchMetadata(preview, for: review))
        XCTAssertEqual(workspace.library.photos, updated)
        XCTAssertEqual(workspace.history.undo, history)
        XCTAssertTrue(workspace.error?.contains("Reopen Batch Change") == true)

        workspace.openBatchMetadata()
        let fresh = try XCTUnwrap(workspace.batchMetadataReview)
        XCTAssertTrue(workspace.applyBatchMetadata(
            fresh.preview(caption: nil, keywordMode: .replace, keywords: "Beach"), for: fresh))
        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        XCTAssertFalse(reopened.canUndo)
        XCTAssertEqual(reopened.library.version, 1)
        XCTAssertEqual(reopened.library.photos.map(\.caption), [first.caption, second.caption])
        XCTAssertEqual(reopened.library.photos.map(\.keywords), ["Beach", "Beach"])
    }

    func testGroupedUndoPreservesUntouchedFieldsAndSurvivingPhotosAfterPurge() throws {
        let first = photo("First", caption: "One", keywords: "Old")
        let second = photo("Second", caption: "Two", keywords: "Older")
        var library = Library()
        library.photos = [first, second]
        let review = BatchMetadataReview(photos: library.photos)
        let preview = review.preview(caption: nil, keywordMode: .replace, keywords: "New")
        var history = EditHistory()
        history.record(.batchMetadata(try XCTUnwrap(review.apply(preview, to: &library))))

        library.photos.removeFirst()
        library.photos[0].caption = "Newer caption"
        history.discardEmptiedTrash(photoIDs: [first.id], originalIDs: [first.originalID])
        XCTAssertNotNil(history.step(in: &library, redoing: false))
        XCTAssertEqual(library.photos[0].keywords, second.keywords)
        XCTAssertEqual(library.photos[0].caption, "Newer caption")
        XCTAssertNotNil(history.step(in: &library, redoing: true))
        XCTAssertEqual(library.photos[0].keywords, "New")
    }

    private func photo(_ name: String, caption: String, keywords: String, projectID: UUID? = nil) -> Photo {
        var photo = Photo(filename: name + ".jpg", originalName: name + ".jpg", projectID: projectID,
                          width: 20, height: 16, camera: "", captureDate: "", sha256: name)
        photo.caption = caption
        photo.keywords = keywords
        return photo
    }

    private func fixture() throws -> (URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueMetadata-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        return (root, preferences)
    }

    private func cleanUp(_ root: URL, _ preferences: UserDefaults) {
        preferences.removePersistentDomain(forName: root.lastPathComponent)
        try? FileManager.default.removeItem(at: root)
    }
}
