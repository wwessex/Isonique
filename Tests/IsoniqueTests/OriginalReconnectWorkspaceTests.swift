import XCTest
import IsoniqueCore
@testable import Isonique

final class OriginalReconnectWorkspaceTests: XCTestCase {
    @MainActor
    func testReconnectRefreshesUnavailableFilterAndKeepsCatalogueEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueReconnectWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let workspace = Workspace(libraryRoot: repo.root)
        let original = folder.appendingPathComponent("Photo.jpg")
        try Data([1, 2, 3]).write(to: original)
        var photo = Photo(filename: "record.jpg", originalName: "Photo.jpg", projectID: nil, width: 8, height: 8,
                          camera: "", captureDate: "", sha256: try LibraryRepository.digest(original))
        photo.referencedPath = folder.appendingPathComponent("Moved/Photo.jpg").path
        photo.adjustments.exposure = 0.75
        var draft = workspace.library
        draft.version = 2
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.originalFilter = .unavailable
        workspace.selection = photo.id
        XCTAssertEqual(workspace.selected?.id, photo.id)
        let revision = workspace.originalStatusRevision

        await workspace.reconnectOriginals(in: folder)

        XCTAssertFalse(workspace.busy)
        XCTAssertNil(workspace.originalReconnectTask)
        XCTAssertNil(workspace.error)
        XCTAssertEqual(workspace.originalReconnectReport?.reconnected, ["Photo.jpg"])
        XCTAssertEqual(workspace.originalStatusRevision, revision + 1)
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.originalFilter = .all
        XCTAssertEqual(workspace.photos.first?.referencedPath, original.path)
        XCTAssertEqual(try repo.load().photos.first?.adjustments.exposure, 0.75)
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
    }
}
