import IsoniqueCore
import MapKit
import XCTest
@testable import Isonique

final class GPXWaypointAssignmentTests: XCTestCase {
    @MainActor
    func testWaypointPreviewScopesSelectedVersionsAndSupportsCancelAndPersistentUndoRedo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueWaypoint-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let libraryRoot = root.appendingPathComponent("Library")
        let model = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        let project = Collection(name: "Walk")
        let otherProject = Collection(name: "Another walk")
        let original = root.appendingPathComponent("Photo.jpg")
        let originalBytes = Data("Test original".utf8)
        try originalBytes.write(to: original)
        let oldLocation = try XCTUnwrap(GPSCoordinates(latitude: 50, longitude: 0))
        var first = photo("Photo.jpg", in: project.id)
        first.referencedPath = original.path
        first.locationOverride = .assigned(oldLocation)
        let untagged = photo("Untagged.jpg", in: project.id)
        let outside = photo("Outside.jpg", in: otherProject.id)
        var trashed = photo("Trashed.jpg", in: project.id)
        trashed.trashedAt = .now

        var draft = model.library
        draft.version = 2
        draft.projects = [project, otherProject]
        draft.photos = [first, untagged, outside, trashed]
        let sibling = try XCTUnwrap(draft.createVersion(of: first.id, from: .current))
        XCTAssertTrue(model.commit(draft), model.error ?? "Could not save fixture")
        model.scope = "project:\(project.id)"
        model.selection = first.id
        model.choosePresentation(.places)

        let url = root.appendingPathComponent("Stops.gpx")
        try """
        <gpx xmlns="http://www.topografix.com/GPX/1/0">
          <wpt lat="51" lon="-1"><name>Camp</name></wpt>
          <wpt lat="52" lon="-2"><name>Trailhead</name></wpt>
        </gpx>
        """.write(to: url, atomically: true, encoding: .utf8)
        await model.importProjectGPXTrack(from: url, into: project.id)
        let track = try XCTUnwrap(model.visibleGPXTracks.first)
        let waypoint = try XCTUnwrap(track.waypoints?.last)
        XCTAssertEqual(model.library.version, 18)

        let map = PhotoMapView(accessibilityLabel: "Test Places")
        let coordinator = PlacesMap.Coordinator()
        coordinator.updateTrackOverlays(model.visibleGPXTracks, on: map)
        XCTAssertTrue(map.overlays.isEmpty)
        XCTAssertEqual(map.annotations.compactMap { $0 as? PlacesMap.WaypointPin }.count, 2)
        let pin = try XCTUnwrap(map.annotations.compactMap { $0 as? PlacesMap.WaypointPin }
            .first { $0.waypointID == waypoint.id })
        coordinator.onSelectWaypoint = { model.openGPXWaypointAssignment(trackID: $0, waypointID: $1) }
        let marker = try XCTUnwrap(coordinator.mapView(map, viewFor: pin))
        coordinator.mapView(map, didSelect: marker)
        let cancelled = try XCTUnwrap(model.gpxWaypointAssignment)
        XCTAssertEqual(cancelled.initialWaypointID, waypoint.id)
        XCTAssertEqual(cancelled.initialPhotoID, first.id)
        XCTAssertFalse(model.photos.contains { $0.id == untagged.id })
        XCTAssertEqual(Set(cancelled.locationEdit.photos.map(\.id)), [first.id, sibling.id, untagged.id])

        let catalogue = libraryRoot.appendingPathComponent("catalog.json")
        let baseline = try Data(contentsOf: catalogue)
        let chosen = Set([first.id, untagged.id])
        XCTAssertEqual(Set(cancelled.locationEdit.changes(to: waypoint.coordinates, restrictedTo: chosen).map(\.photoID)), chosen)
        model.gpxWaypointAssignment = nil
        XCTAssertFalse(model.applyGPXWaypointAssignment(cancelled.id, waypointID: waypoint.id, photoIDs: chosen))
        XCTAssertEqual(try Data(contentsOf: catalogue), baseline)
        XCTAssertTrue(model.history.undo.isEmpty)

        model.scope = "project:\(otherProject.id)"
        coordinator.updateTrackOverlays(model.visibleGPXTracks, on: map, replacing: true)
        XCTAssertTrue(map.annotations.isEmpty)
        coordinator.mapView(map, didSelect: marker)
        model.openGPXWaypointAssignment(trackID: track.id, waypointID: waypoint.id)
        XCTAssertNil(model.gpxWaypointAssignment)

        model.scope = "project:\(project.id)"
        model.search = "Untagged"
        model.openGPXWaypointAssignment(trackID: track.id)
        XCTAssertEqual(model.gpxWaypointAssignment?.locationEdit.photos.map(\.id), [untagged.id])
        model.search = ""
        model.openGPXWaypointAssignment(trackID: track.id, waypointID: waypoint.id)
        let review = try XCTUnwrap(model.gpxWaypointAssignment)
        XCTAssertFalse(model.applyGPXWaypointAssignment(review.id, waypointID: waypoint.id, photoIDs: [first.id, outside.id]))
        model.error = nil
        model.scope = "all"
        XCTAssertFalse(model.applyGPXWaypointAssignment(review.id, waypointID: waypoint.id, photoIDs: chosen))
        XCTAssertEqual(try Data(contentsOf: catalogue), baseline)
        model.error = nil

        model.scope = "project:\(project.id)"
        model.openGPXWaypointAssignment(trackID: track.id, waypointID: waypoint.id)
        let assignment = try XCTUnwrap(model.gpxWaypointAssignment)
        XCTAssertTrue(model.applyGPXWaypointAssignment(assignment.id, waypointID: waypoint.id, photoIDs: chosen))
        XCTAssertNil(model.gpxWaypointAssignment)
        XCTAssertEqual(model.history.undo.count, 1)
        let reopened = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        XCTAssertNil(reopened.error)
        reopened.scope = "project:\(project.id)"
        reopened.choosePresentation(.places)
        XCTAssertEqual(reopened.visibleGPXTracks.first?.waypoints, track.waypoints)
        XCTAssertEqual(Set(PhotoPlace.grouped(reopened.photos).first { $0.id == waypoint.coordinates }?.photos.map(\.id) ?? []), chosen)
        XCTAssertEqual(reopened.library.photos.first { $0.id == sibling.id }?.cataloguedLocation, oldLocation)
        XCTAssertNil(reopened.library.photos.first { $0.id == outside.id }?.cataloguedLocation)
        reopened.undoEdit()
        XCTAssertEqual(reopened.library.photos.first { $0.id == first.id }?.cataloguedLocation, oldLocation)
        XCTAssertNil(reopened.library.photos.first { $0.id == untagged.id }?.cataloguedLocation)
        reopened.redoEdit()
        XCTAssertEqual(Set(PhotoPlace.grouped(reopened.photos).first { $0.id == waypoint.coordinates }?.photos.map(\.id) ?? []), chosen)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    private func photo(_ name: String, in projectID: UUID) -> Photo {
        Photo(filename: name, originalName: name, projectID: projectID, width: 32, height: 24,
              camera: "", captureDate: "", sha256: name)
    }
}
