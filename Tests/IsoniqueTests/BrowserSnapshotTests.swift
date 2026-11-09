import XCTest
import IsoniqueCore
@testable import Isonique

final class BrowserSnapshotTests: XCTestCase {
    @MainActor
    func testSnapshotTracksSearchSortScopeAndMetadataEdits() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace(libraryRoot: folder)
        let project = Collection(name: "Portraits")
        var a = photo("A.jpg", projectID: project.id)
        a.caption = "Studio"
        var b = photo("B.jpg")
        b.caption = "Landscape"
        var draft = workspace.library
        draft.photos = [b, a]
        draft.projects = [project]
        XCTAssertTrue(workspace.commit(draft))
        workspace.sort = .name
        workspace.selection = a.id
        XCTAssertEqual(workspace.photos.map(\.id), [a.id, b.id])
        XCTAssertEqual(workspace.selected?.id, a.id)
        workspace.sortDescending = true
        XCTAssertEqual(workspace.photos.map(\.id), [b.id, a.id])
        workspace.search = "studio"
        XCTAssertEqual(workspace.photos.map(\.id), [a.id])
        workspace.edit { $0.caption = "New caption" }
        XCTAssertTrue(workspace.photos.isEmpty)
        XCTAssertNil(workspace.selected)
        workspace.search = ""
        workspace.scope = "project:\(project.id)"
        XCTAssertEqual(workspace.photos.map(\.id), [a.id])
        XCTAssertEqual(workspace.selected?.caption, "New caption")
        workspace.ratingFilter = .fourAndAbove
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.ratingFilter = .all
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .filename, comparison: .equals, value: "B.jpg")]
        workspace.advancedSearch = query
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.scope = "all"
        XCTAssertEqual(workspace.photos.map(\.id), [b.id])
    }

    @MainActor
    func testAvailabilityFiltersAndSmartAlbumsReadLiveFiles() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let workspace = Workspace(libraryRoot: folder)
        let item = photo("External.jpg")
        let original = folder.appendingPathComponent("Originals/External.jpg")
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .availability, comparison: .equals, value: "true")]
        var rule = SmartAlbumRule()
        rule.query = query
        var album = Collection(name: "Online")
        album.rule = rule
        var draft = workspace.library
        draft.photos = [item]
        draft.albums = [album]
        draft.version = 2
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = item.id

        workspace.originalFilter = .unavailable
        XCTAssertEqual(workspace.selected?.id, item.id)
        try Data([1]).write(to: original)
        XCTAssertTrue(workspace.photos.isEmpty)
        XCTAssertNil(workspace.selected)
        workspace.originalFilter = .all
        workspace.advancedSearch = query
        XCTAssertEqual(workspace.photos.map(\.id), [item.id])
        try FileManager.default.removeItem(at: original)
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.advancedSearch = nil
        workspace.scope = "album:\(album.id)"
        XCTAssertTrue(workspace.photos.isEmpty)
        try Data([2]).write(to: original)
        XCTAssertEqual(workspace.selected?.id, item.id)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueBrowserSnapshot-\(UUID().uuidString)")
        return try LibraryRepository.createEmpty(at: url).root
    }

    private func photo(_ filename: String, projectID: UUID? = nil) -> Photo {
        Photo(filename: filename, originalName: filename, projectID: projectID, width: 8, height: 8,
              camera: "", captureDate: "", sha256: "fixture")
    }
}
