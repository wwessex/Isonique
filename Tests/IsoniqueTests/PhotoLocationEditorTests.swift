import IsoniqueCore
import XCTest
@testable import Isonique

final class PhotoLocationEditorTests: XCTestCase {
    @MainActor
    func testLocationEditsUpdatePlacesAndSmartAlbumsAndSurviveReopening() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueLocation-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let libraryRoot = root.appendingPathComponent("Library")
        let workspace = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        let repository = try XCTUnwrap(workspace.repository)
        let london = try XCTUnwrap(GPSCoordinates(latitude: 51.5, longitude: -0.125))
        let sydney = try XCTUnwrap(GPSCoordinates(latitude: "-33,875°", longitude: "+151.25"))
        let original = root.appendingPathComponent("London.jpg")
        let bytes = Data("Original fixture bytes".utf8)
        try bytes.write(to: original)
        var londonPhoto = makePhoto("London.jpg")
        londonPhoto.referencedPath = original.path
        londonPhoto.gpsIndex = try JSONDecoder().decode(GPSIndex.self, from: JSONEncoder().encode(["coordinates": london]))
        let untagged = makePhoto("Untagged.jpg")
        var draft = workspace.library
        draft.photos = [londonPhoto, untagged]
        let version = try XCTUnwrap(draft.createVersion(of: londonPhoto.id, from: .current))
        let sydneyAlbum = album("Sydney", PhotoQueryCriterion(field: .gpsLocation, comparison: .withinRadius,
                                                               gpsRadius: GPSRadiusRule(latitude: "-33.875", longitude: "151.25", kilometres: "1")))
        let missingAlbum = album("Missing GPS", PhotoQueryCriterion(field: .gpsLocation, comparison: .isMissing))
        draft.albums = [sydneyAlbum, missingAlbum]
        XCTAssertTrue(workspace.commit(draft))

        workspace.batchMode = true
        workspace.batchSelection = [londonPhoto.id, untagged.id]
        workspace.openLocationEditor(.assign)
        let assignment = try XCTUnwrap(workspace.locationEditor)
        XCTAssertEqual(assignment.changes(to: nil), [])
        XCTAssertTrue(workspace.applyLocationEdit(assignment, coordinates: sydney))
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.library.version, 16)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertEqual(workspace.library.photos.first { $0.id == version.id }?.cataloguedLocation, london)
        XCTAssertEqual(workspace.library.photos.first { $0.id == londonPhoto.id }?.gpsIndex?.coordinates, london)

        let parked = root.appendingPathComponent("Offline.jpg")
        try FileManager.default.moveItem(at: original, to: parked)
        let reopened = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        reopened.choosePresentation(.places)
        XCTAssertEqual(Set(PhotoPlace.grouped(reopened.photos).map(\.id)), [london, sydney])
        XCTAssertEqual(reopened.isOriginalAvailable(londonPhoto), false)
        reopened.scope = "album:\(sydneyAlbum.id)"
        XCTAssertEqual(Set(reopened.photos.map(\.id)), [londonPhoto.id, untagged.id])
        reopened.undoEdit()
        XCTAssertTrue(reopened.photos.isEmpty)
        reopened.redoEdit()
        XCTAssertEqual(Set(reopened.photos.map(\.id)), [londonPhoto.id, untagged.id])

        reopened.selection = londonPhoto.id
        reopened.openLocationEditor(.clear)
        let clear = try XCTUnwrap(reopened.locationEditor)
        XCTAssertTrue(reopened.applyLocationEdit(clear, coordinates: nil))
        XCTAssertEqual(reopened.photos.map(\.id), [untagged.id])
        reopened.scope = "all"
        XCTAssertFalse(reopened.photos.contains { $0.id == londonPhoto.id })
        reopened.choosePresentation(.grid)
        reopened.scope = "album:\(missingAlbum.id)"
        XCTAssertEqual(reopened.photos.map(\.id), [londonPhoto.id])

        let afterClear = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        XCTAssertEqual(afterClear.library.photos.first { $0.id == londonPhoto.id }?.locationOverride, .cleared)
        afterClear.undoEdit()
        XCTAssertEqual(afterClear.library.photos.first { $0.id == londonPhoto.id }?.cataloguedLocation, sydney)
        afterClear.redoEdit()
        XCTAssertNil(afterClear.library.photos.first { $0.id == londonPhoto.id }?.cataloguedLocation)
        afterClear.selection = londonPhoto.id
        afterClear.openLocationEditor(.useOriginal)
        XCTAssertTrue(afterClear.applyLocationEdit(try XCTUnwrap(afterClear.locationEditor), coordinates: nil))
        XCTAssertEqual(try repository.load().photos.first { $0.id == londonPhoto.id }?.cataloguedLocation, london)
        XCTAssertEqual(try Data(contentsOf: parked), bytes)
    }

    @MainActor
    func testStaleOrUnchangedLocationEditDoesNotWrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueLocation-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let first = makePhoto("First.jpg")
        let second = makePhoto("Second.jpg")
        var draft = workspace.library
        draft.photos = [first, second]
        XCTAssertTrue(workspace.commit(draft))
        workspace.selection = first.id
        workspace.openLocationEditor(.assign)
        let assignment = try XCTUnwrap(workspace.locationEditor)
        let point = try XCTUnwrap(GPSCoordinates(latitude: 1, longitude: 2))
        let catalogue = root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        workspace.selection = second.id
        XCTAssertFalse(workspace.applyLocationEdit(assignment, coordinates: point))
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        workspace.selection = first.id
        workspace.error = nil
        XCTAssertTrue(workspace.applyLocationEdit(assignment, coordinates: point))
        workspace.openLocationEditor(.assign)
        let saved = try Data(contentsOf: catalogue)
        XCTAssertFalse(workspace.applyLocationEdit(try XCTUnwrap(workspace.locationEditor), coordinates: point))
        XCTAssertFalse(workspace.applyLocationEdit(assignment, coordinates: point))
        XCTAssertEqual(try Data(contentsOf: catalogue), saved)
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertNil(GPSCoordinates(latitude: "90.0001", longitude: "0"))
        XCTAssertNil(GPSCoordinates(latitude: "0", longitude: "nan"))
    }

    private func makePhoto(_ name: String) -> Photo {
        Photo(filename: name, originalName: name, projectID: nil,
              width: 32, height: 24, camera: "", captureDate: "", sha256: name)
    }

    private func album(_ name: String, _ criterion: PhotoQueryCriterion) -> Collection {
        var album = Collection(name: name)
        var rule = SmartAlbumRule()
        var query = PhotoQuery()
        query.criteria = [criterion]
        rule.query = query
        album.rule = rule
        return album
    }
}
