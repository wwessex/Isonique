import XCTest
import IsoniqueCore
@testable import Isonique

final class WorkspaceTests: XCTestCase {
    @MainActor
    func testTrashFiltersSelectionUndoRedoAndRestart() async throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        let project = Collection(name: "Shoot")
        var draft = workspace.library
        draft.projects = [project]
        var photo = Photo(filename: "a.png", originalName: "a.png", projectID: project.id,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        photo.rating = 5; photo.flagged = true
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.scope = "project:\(project.id)"
        workspace.selection = photo.id
        workspace.setPhotosTrashed(workspace.selectedTrashActionIDs, trashed: true)
        XCTAssertNil(workspace.selected)
        workspace.scope = "flagged"
        XCTAssertTrue(workspace.photos.isEmpty)

        workspace.undoEdit()
        XCTAssertEqual(workspace.selected, photo)
        workspace.redoEdit()
        XCTAssertTrue(workspace.photos.isEmpty)

        let reopened = Workspace(libraryRoot: root)
        XCTAssertTrue(reopened.photos.isEmpty)
        reopened.scope = "trash"
        reopened.batchMode = true
        reopened.batchSelection = [photo.id, UUID()]
        XCTAssertEqual(reopened.selectedTrashActionIDs, [photo.id])
        reopened.setPhotosTrashed(reopened.selectedTrashActionIDs, trashed: false)
        XCTAssertTrue(reopened.photos.isEmpty)
        reopened.scope = "project:\(project.id)"
        XCTAssertEqual(reopened.photos, [photo])
        XCTAssertEqual(try reopened.repository?.load().activePhotos, [photo])
    }

    @MainActor
    func testFailedSavePreservesPublishedEditAndUndoState() async throws {
        let root = try temporaryLibrary()
        let fm = FileManager.default
        defer { try? fm.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        let photo = Photo(filename: "a.png", originalName: "a.png", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        var draft = workspace.library
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = photo.id
        workspace.edit { $0.caption = "Saved" }
        XCTAssertEqual(workspace.selected?.caption, "Saved")
        let catalog = root.appendingPathComponent("catalog.json")
        let saved = root.appendingPathComponent("saved.json")
        try fm.moveItem(at: catalog, to: saved)
        try fm.createDirectory(at: catalog, withIntermediateDirectories: false)

        workspace.edit { $0.caption = "Write failed" }
        workspace.undoEdit()
        workspace.setPhotosTrashed([photo.id], trashed: true)
        XCTAssertEqual(workspace.selected?.caption, "Saved")
        XCTAssertNil(workspace.selected?.trashedAt)
        XCTAssertEqual(workspace.history.undo, [.edit(photo)])
        XCTAssertFalse(workspace.canRedo)
        XCTAssertNotNil(workspace.error)

        try fm.removeItem(at: catalog)
        try fm.moveItem(at: saved, to: catalog)
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected, photo)
        XCTAssertEqual(try workspace.repository?.load().photos, [photo])
    }

    @MainActor
    func testOriginalStorageFiltersAndHistoryPreserveRelinkedPath() async throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        var photo = Photo(filename: "a.png", originalName: "a.png", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        photo.referencedPath = "/private/tmp/Isonique-offline-\(UUID().uuidString).png"
        var draft = workspace.library
        draft.version = 2
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = photo.id
        workspace.originalFilter = .managed
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.originalFilter = .referenced
        XCTAssertEqual(workspace.photos, [photo])
        workspace.originalFilter = .unavailable
        XCTAssertEqual(workspace.photos, [photo])
        workspace.edit { $0.caption = "Retain Undo" }

        draft = workspace.library
        let relinked = "/private/tmp/Isonique-relinked-\(UUID().uuidString).png"
        draft.photos[0].referencedPath = relinked
        XCTAssertTrue(workspace.commit(draft))
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.caption, "")
        XCTAssertEqual(workspace.selected?.referencedPath, relinked)
    }

    @MainActor
    func testAdvancedSearchAndSmartAlbumShareScopeAndLiveEdits() async throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        let project = Collection(name: "Client")
        var photo = Photo(filename: "a.png", originalName: "portrait.png", projectID: project.id,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        photo.caption = "Ready for delivery"
        var unassigned = photo
        unassigned.id = UUID()
        unassigned.filename = "b.png"
        unassigned.projectID = nil
        var draft = workspace.library
        draft.projects = [project]
        draft.photos = [photo, unassigned]
        XCTAssertTrue(workspace.commit(draft))
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .caption, comparison: .contains, value: "DELIVERY")]
        XCTAssertEqual(workspace.filteredPhotos(advancedQuery: query).count, 2)
        workspace.scope = "project:\(project.id)"
        workspace.advancedSearch = query
        XCTAssertEqual(workspace.photos, [photo])

        var rule = SmartAlbumRule()
        rule.query = query
        rule.projectID = project.id
        XCTAssertTrue(workspace.saveSmartAlbum(name: "Delivery", rule: rule))
        let album = try XCTUnwrap(workspace.library.albums.first)
        XCTAssertEqual(workspace.library.version, 2)
        XCTAssertNil(workspace.advancedSearch)
        XCTAssertEqual(workspace.photos, [photo])
        workspace.selection = photo.id
        workspace.edit { $0.caption = "Hold for approval" }
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.undoEdit()
        XCTAssertEqual(workspace.photos, [photo])
        let reopened = Workspace(libraryRoot: root)
        reopened.scope = "album:\(album.id)"
        XCTAssertEqual(reopened.photos, [photo])
    }

    @MainActor
    func testFlipRetainsCropAndParticipatesInHistory() async throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = Workspace(libraryRoot: root)
        var photo = Photo(filename: "a.png", originalName: "a.png", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.crop = PhotoCrop(x: 0.125, y: 0.25, width: 0.5, height: 0.5)
        var draft = workspace.library
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = photo.id
        workspace.flip(.horizontal)
        XCTAssertEqual(workspace.selected?.adjustments.flipHorizontal, true)
        XCTAssertEqual(workspace.selected?.adjustments.crop?.x, 0.375)
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected, photo)
        workspace.redoEdit()
        XCTAssertEqual(try workspace.repository?.load().photos.first, workspace.selected)
    }

    @MainActor
    func testReviewCullingLabelFilterUndoAndLabelNamePreferences() async throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "IsoniqueTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        var first = Photo(filename: "a.png", originalName: "a.png", projectID: nil,
                           width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        first.importedAt = Date(timeIntervalSinceReferenceDate: 1)
        var second = first
        second.id = UUID()
        second.filename = "b.png"
        second.importedAt = Date(timeIntervalSinceReferenceDate: 2)
        var draft = workspace.library
        draft.photos = [first, second]
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = first.id
        workspace.ratingFilter = .unrated
        workspace.setReviewRating(5)
        XCTAssertEqual(workspace.selection, second.id)
        XCTAssertEqual(workspace.photos.map(\.id), [second.id])
        workspace.setColorLabel(.green)
        XCTAssertEqual(workspace.selected?.colorLabel, .green)
        workspace.ratingFilter = .all
        workspace.colorFilter = .color(.green)
        XCTAssertEqual(workspace.photos.map(\.id), [second.id])
        workspace.rename(.green, to: "Ready to send")
        workspace.undoEdit()
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.redoEdit()
        XCTAssertEqual(workspace.photos.map(\.id), [second.id])

        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        XCTAssertEqual(reopened.name(for: .green), "Ready to send")
        XCTAssertEqual(reopened.library.photos[1].colorLabel, .green)
        reopened.rename(.green, to: "")
        XCTAssertEqual(reopened.name(for: .green), "Green")
    }

    @MainActor
    func testVersionCommandsComparisonAndPersistentUndoRedo() async throws {
        let root = try temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "IsoniqueVersionsTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        var photo = Photo(filename: "a.png", originalName: "a.png", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.exposure = 1
        var draft = workspace.library
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = photo.id
        workspace.createVersion(from: .original)
        let neutral = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(neutral.adjustments, Adjustments())
        workspace.startComparison()
        XCTAssertEqual(workspace.comparisonPhoto?.id, neutral.id)
        XCTAssertEqual(workspace.selected?.id, photo.id)
        workspace.selectBrowserPhoto(neutral.id)
        XCTAssertEqual(workspace.comparisonPhoto?.id, photo.id)
        workspace.chooseTool(.crop)
        XCTAssertNil(workspace.comparisonID)
        workspace.renameVersion(neutral.id, to: "Deliverable")
        XCTAssertEqual(workspace.selected?.displayName, "Deliverable")
        workspace.setPhotosTrashed([neutral.id], trashed: true)
        XCTAssertEqual(workspace.photos, [photo])
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.displayName, "Deliverable")
        workspace.undoEdit()
        workspace.undoEdit()
        XCTAssertEqual(workspace.photos, [photo])

        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        XCTAssertTrue(reopened.canRedo)
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected?.id, neutral.id)
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected?.displayName, "Deliverable")
        reopened.search = "Deliverable"
        XCTAssertEqual(reopened.photos.map(\.id), [neutral.id])
        reopened.startComparison()
        XCTAssertEqual(reopened.comparisonPhoto?.id, photo.id)
        XCTAssertEqual(reopened.selected?.id, neutral.id)
        var rule = SmartAlbumRule()
        rule.projectID = UUID()
        XCTAssertTrue(reopened.saveSmartAlbum(name: "Still compatible", rule: rule))
        XCTAssertEqual(reopened.library.version, 3)
    }

    private func temporaryLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueUI-\(UUID().uuidString)")
        return try LibraryRepository.createEmpty(at: root).root
    }
}
