import IsoniqueCore
import XCTest
@testable import Isonique

final class SavedPlaceTests: XCTestCase {
    func testCreateRenameAndRemovePersistAcrossPreferenceInstances() throws {
        let suite = "IsoniqueSavedPlaces-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let point = try XCTUnwrap(GPSCoordinates(latitude: 51.5, longitude: -0.125))
        let store = SavedPlaceStore(preferences: preferences)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertThrowsError(try store.create(named: " \n ", coordinates: point))
        let studio = try store.create(named: "  Studio  ", coordinates: point)
        XCTAssertEqual(studio.name, "Studio")
        let other = try store.create(named: "Client site", coordinates: point)

        let reopened = SavedPlaceStore(preferences: try XCTUnwrap(UserDefaults(suiteName: suite)))
        XCTAssertEqual(try reopened.load(), [other, studio])
        XCTAssertThrowsError(try reopened.create(named: "studio", coordinates: point))
        XCTAssertThrowsError(try reopened.rename(studio.id, to: "client site"))
        XCTAssertEqual(try reopened.load(), [other, studio])

        let renamed = try reopened.rename(studio.id, to: "  Studio entrance ")
        XCTAssertEqual(renamed.id, studio.id)
        XCTAssertEqual(renamed.name, "Studio entrance")
        XCTAssertEqual(renamed.coordinates, point)
        XCTAssertEqual(try store.load(), [other, renamed])

        try reopened.remove(renamed.id)
        XCTAssertThrowsError(try store.rename(renamed.id, to: "Stale edit"))
        XCTAssertEqual(try SavedPlaceStore(preferences: XCTUnwrap(UserDefaults(suiteName: suite))).load(), [other])
    }

    @MainActor
    func testReuseAcrossLibrariesPreviewsBeforeAssignmentAndRemovalKeepsAssignedCoordinates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueSavedPlaces-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let source = Workspace(libraryRoot: root.appendingPathComponent("Source"), preferences: preferences)
        let sourceCatalogue = try XCTUnwrap(source.repository).root.appendingPathComponent("catalog.json")
        let sourceBefore = try Data(contentsOf: sourceCatalogue)
        var sourceDraft = PhotoLocationDraft()
        sourceDraft.latitude = "-33.875"
        sourceDraft.longitude = "151.25"
        let point = try XCTUnwrap(sourceDraft.coordinates)
        let place = try SavedPlaceStore(preferences: source.preferences).create(named: "Studio", coordinates: point)
        XCTAssertEqual(try Data(contentsOf: sourceCatalogue), sourceBefore)

        let destination = Workspace(libraryRoot: root.appendingPathComponent("Destination"), preferences: preferences)
        let repository = try XCTUnwrap(destination.repository)
        let photo = Photo(filename: "Photo.jpg", originalName: "Photo.jpg", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "fixture")
        var library = destination.library
        library.photos = [photo]
        XCTAssertTrue(destination.commit(library))
        destination.selection = photo.id
        destination.openLocationEditor(.assign)
        let edit = try XCTUnwrap(destination.locationEditor)
        let store = SavedPlaceStore(preferences: destination.preferences)
        let reused = try XCTUnwrap(store.load().first)
        let draft = PhotoLocationDraft(reused.coordinates)
        XCTAssertEqual(reused, place)
        XCTAssertEqual(edit.changes(to: draft.coordinates),
                       [PhotoLocationChange(photoID: photo.id, location: .assigned(point))])
        XCTAssertNil(try repository.load().photos.first?.cataloguedLocation)

        XCTAssertTrue(destination.applyLocationEdit(edit, coordinates: draft.coordinates))
        XCTAssertEqual(try repository.load().photos.first?.cataloguedLocation, point)
        XCTAssertEqual(destination.history.undo.count, 1)
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let afterAssignment = try Data(contentsOf: catalogue)
        _ = try store.rename(place.id, to: "Studio entrance")
        try store.remove(place.id)
        XCTAssertTrue(try store.load().isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogue), afterAssignment)
        XCTAssertEqual(try repository.load().photos.first?.cataloguedLocation, point)
    }
}
