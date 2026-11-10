import Foundation
import IsoniqueCore
import MapKit
import XCTest
@testable import Isonique

final class PlacesBrowserTests: XCTestCase {
    @MainActor
    func testPlacesScopesAndSelectionIncludeOfflineOriginals() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniquePlaces-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = Workspace(libraryRoot: root.appendingPathComponent("Library"), preferences: preferences)
        let local = Collection(name: "London Project")
        let remote = Collection(name: "Sydney Project")
        let london = try XCTUnwrap(GPSCoordinates(latitude: 51.5, longitude: -0.125))
        let sydney = try XCTUnwrap(GPSCoordinates(latitude: -33.875, longitude: 151.25))
        let original = root.appendingPathComponent("London.jpg")
        try Data("Referenced original".utf8).write(to: original)
        var first = try photo("London.jpg", project: local.id, coordinates: london)
        first.referencedPath = original.path
        let second = try photo("Sydney.jpg", project: remote.id, coordinates: sydney)
        let untagged = try photo("Untagged.jpg", project: local.id, coordinates: nil)
        var trashed = try photo("Trashed.jpg", project: local.id,
                                coordinates: GPSCoordinates(latitude: 47.5, longitude: 19))
        trashed.trashedAt = .now

        var draft = workspace.library
        draft.projects = [local, remote]
        draft.photos = [first, second, untagged, trashed]
        let version = try XCTUnwrap(draft.createVersion(of: first.id, from: .current))
        XCTAssertTrue(workspace.commit(draft))
        let catalogue = try XCTUnwrap(workspace.repository).root.appendingPathComponent("catalog.json")
        let catalogueBefore = try Data(contentsOf: catalogue)
        XCTAssertEqual(workspace.isOriginalAvailable(first), true)
        workspace.selection = untagged.id
        workspace.choosePresentation(.places)
        XCTAssertEqual(workspace.presentation, .places)
        XCTAssertEqual(workspace.scope, "all")
        XCTAssertEqual(Set(workspace.photos.map(\.id)), [first.id, second.id, version.id])
        XCTAssertNotEqual(workspace.selected?.id, untagged.id)
        let groups = PhotoPlace.grouped(workspace.photos)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.first { $0.id == london }?.photos.map(\.id) ?? []), [first.id, version.id])

        workspace.selectPlace(sydney)
        XCTAssertEqual(workspace.selected?.id, second.id)
        workspace.selectBrowserPhoto(version.id)
        workspace.selectPlace(london)
        XCTAssertEqual(workspace.selected?.id, version.id, "Selecting the same pin keeps the chosen version")
        try FileManager.default.removeItem(at: original)
        await workspace.reloadLibrary()
        XCTAssertEqual(workspace.isOriginalAvailable(first), false)
        XCTAssertEqual(workspace.selected?.id, version.id)
        XCTAssertEqual(PhotoPlace.grouped(workspace.photos).first { $0.id == london }?.photos.count, 2)

        workspace.scope = "project:\(local.id)"
        XCTAssertEqual(workspace.presentation, .places)
        XCTAssertEqual(Set(workspace.photos.map(\.id)), [first.id, version.id])
        workspace.selectPlace(sydney)
        XCTAssertEqual(workspace.selected?.id, version.id, "An out-of-scope pin cannot change selection")
        workspace.choosePresentation(.viewer)
        XCTAssertEqual(workspace.presentation, .viewer)
        XCTAssertEqual(workspace.selected?.id, version.id)
        workspace.exitViewer()
        XCTAssertEqual(workspace.presentation, .places)
        workspace.scope = "project:\(remote.id)"
        XCTAssertEqual(workspace.photos.map(\.id), [second.id])
        workspace.selectPlace(sydney)
        XCTAssertEqual(workspace.selected?.id, second.id)

        workspace.scope = "all"
        workspace.search = "Untagged"
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.choosePresentation(.grid)
        XCTAssertEqual(workspace.photos.map(\.id), [untagged.id])
        XCTAssertEqual(try Data(contentsOf: catalogue), catalogueBefore)
    }

    func testMapFramingKeepsDistantPinsAndWrapsAtTheDateLine() throws {
        let london = try XCTUnwrap(GPSCoordinates(latitude: 51.5, longitude: -0.125))
        let sydney = try XCTUnwrap(GPSCoordinates(latitude: -33.875, longitude: 151.25))
        let global = try XCTUnwrap(PlacesMapFraming.bounds(for: [london, sydney]))
        for point in [london, sydney] {
            XCTAssertTrue(global.contains(MKMapPoint(.init(latitude: point.latitude, longitude: point.longitude))))
        }

        let east = try XCTUnwrap(GPSCoordinates(latitude: 0, longitude: 179.9))
        let west = try XCTUnwrap(GPSCoordinates(latitude: 0, longitude: -179.9))
        let wrapped = try XCTUnwrap(PlacesMapFraming.bounds(for: [east, west]))
        XCTAssertTrue(wrapped.spans180thMeridian)
        XCTAssertLessThan(wrapped.width, MKMapRect.world.width / 360)
    }

    private func photo(_ name: String, project: UUID, coordinates: GPSCoordinates?) throws -> Photo {
        var photo = Photo(filename: name, originalName: name, projectID: project,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: name)
        if let coordinates {
            let data = try JSONEncoder().encode(["coordinates": coordinates])
            photo.gpsIndex = try JSONDecoder().decode(GPSIndex.self, from: data)
        }
        return photo
    }
}
