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
        XCTAssertEqual(workspace.history.undo, [photo])
        XCTAssertFalse(workspace.canRedo)
        XCTAssertNotNil(workspace.error)

        try fm.removeItem(at: catalog)
        try fm.moveItem(at: saved, to: catalog)
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected, photo)
        XCTAssertEqual(try workspace.repository?.load().photos, [photo])
    }

    private func temporaryLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueUI-\(UUID().uuidString)")
        return try LibraryRepository.createEmpty(at: root).root
    }
}
