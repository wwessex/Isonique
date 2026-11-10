import IsoniqueCore
import MapKit
import XCTest
@testable import Isonique

final class ProjectGPXOverlayTests: XCTestCase {
    @MainActor
    func testPlacesShowsSavedProjectTrackAndRemovalPreservesAssignedPhotoAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueGPXOverlay-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let libraryRoot = root.appendingPathComponent("Library")
        let model = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        let project = Collection(name: "Walk")
        let emptyProject = Collection(name: "Empty walk")
        let album = Collection(name: "Walk album")
        let original = root.appendingPathComponent("Photo.jpg")
        let originalBytes = Data("Original bytes".utf8)
        try originalBytes.write(to: original)
        var photo = Photo(filename: "Photo.jpg", originalName: "Photo.jpg", projectID: project.id,
                          width: 32, height: 24, camera: "", captureDate: "2026:07:04 11:30:00", sha256: "photo")
        photo.referencedPath = original.path
        photo.albumIDs = [album.id]
        var library = model.library
        library.version = 2
        library.projects = [project, emptyProject]
        library.albums = [album]
        library.photos = [photo]
        XCTAssertTrue(model.commit(library), model.error ?? "Could not save the fixture")
        model.selection = photo.id

        let url = root.appendingPathComponent("Walk.gpx")
        try """
        <gpx><trk><trkseg>
          <trkpt lat="51" lon="-0.125"><time>2026-07-04T11:30:00Z</time></trkpt>
          <trkpt lat="52" lon="-0.25"><time>2026-07-04T11:30:20Z</time></trkpt>
        </trkseg></trk></gpx>
        """.write(to: url, atomically: true, encoding: .utf8)
        model.openGPXLocationEditor(url: url)
        let edit = try XCTUnwrap(model.gpxLocationEditor)
        let preview = try edit.preview(track: GPXTrack(contentsOf: url),
                                       settings: .init(timeZone: .gmt, maximumGap: 30))
        XCTAssertTrue(model.applyGPXLocations(preview, excluding: []))
        model.gpxLocationEditor = nil
        let assigned = try XCTUnwrap(model.selected?.cataloguedLocation)
        XCTAssertEqual(model.history.undo.count, 1)

        model.choosePresentation(.places)
        model.scope = "project:\(project.id)"
        await model.importProjectGPXTrack(from: url, into: project.id)
        XCTAssertNil(model.error)
        let track = try XCTUnwrap(model.visibleGPXTracks.first)
        XCTAssertEqual(model.library.version, 17)
        let coordinator = PlacesMap.Coordinator()
        let map = PhotoMapView(accessibilityLabel: "Test Places")
        coordinator.updateTrackOverlays(model.visibleGPXTracks, on: map)
        let line = try XCTUnwrap(map.overlays.first as? MKPolyline)
        XCTAssertEqual(line.pointCount, 2)
        XCTAssertTrue(coordinator.mapView(map, rendererFor: line) is MKPolylineRenderer)
        XCTAssertEqual(model.photos.first?.cataloguedLocation, assigned)

        model.search = "No matching photos"
        XCTAssertTrue(model.photos.isEmpty)
        XCTAssertEqual(model.visibleGPXTracks.map(\.id), [track.id])
        model.search = ""
        for scope in ["all", "album:\(album.id)", "project:\(emptyProject.id)"] {
            model.scope = scope
            coordinator.updateTrackOverlays(model.visibleGPXTracks, on: map, replacing: true)
            XCTAssertTrue(map.overlays.isEmpty)
        }
        XCTAssertTrue(model.photos.isEmpty)
        await model.importProjectGPXTrack(from: url, into: emptyProject.id)
        let otherTrack = try XCTUnwrap(model.visibleGPXTracks.first)
        XCTAssertNotEqual(track.id, otherTrack.id)
        coordinator.updateTrackOverlays(model.visibleGPXTracks, on: map)
        XCTAssertEqual(map.overlays.count, 1, "A project with no photos can still show a track")
        model.removeGPXTrack(track.id, from: project.id)
        XCTAssertEqual(model.visibleGPXTracks.map(\.id), [otherTrack.id])

        model.scope = "project:\(project.id)"
        model.setGPXTrackVisibility(false, trackID: track.id, in: project.id)
        XCTAssertTrue(model.visibleGPXTracks.isEmpty)
        coordinator.updateTrackOverlays(model.visibleGPXTracks, on: map)
        XCTAssertTrue(map.overlays.isEmpty)
        try FileManager.default.removeItem(at: url)

        let reopened = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        XCTAssertNil(reopened.error)
        reopened.scope = "project:\(project.id)"
        reopened.choosePresentation(.places)
        XCTAssertTrue(reopened.visibleGPXTracks.isEmpty)
        XCTAssertEqual(reopened.placesProject?.gpxTracks?.first?.isVisible, false)
        reopened.setGPXTrackVisibility(true, trackID: track.id, in: project.id)
        XCTAssertEqual(reopened.visibleGPXTracks, [track])
        coordinator.updateTrackOverlays(reopened.visibleGPXTracks, on: map)
        XCTAssertEqual(map.overlays.count, 1)

        reopened.removeGPXTrack(track.id, from: project.id)
        coordinator.updateTrackOverlays(reopened.visibleGPXTracks, on: map)
        XCTAssertTrue(map.overlays.isEmpty)
        let saved = try XCTUnwrap(reopened.repository).load()
        XCTAssertNil(saved.projects.first { $0.id == project.id }?.gpxTracks)
        XCTAssertEqual(saved.projects.first { $0.id == emptyProject.id }?.gpxTracks, [otherTrack])
        XCTAssertEqual(saved.photos.first?.cataloguedLocation, assigned)
        XCTAssertEqual(PhotoPlace.grouped(reopened.photos).map(\.id), [assigned])
        XCTAssertEqual(reopened.history.undo.count, 1)
        reopened.undoEdit()
        XCTAssertTrue(reopened.photos.isEmpty)
        reopened.redoEdit()
        XCTAssertEqual(reopened.photos.first?.cataloguedLocation, assigned)
        XCTAssertTrue(reopened.visibleGPXTracks.isEmpty)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    func testTrackPolylinesKeepSegmentsSeparateAndSplitAtAntimeridian() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).gpx")
        defer { try? FileManager.default.removeItem(at: url) }
        try """
        <gpx><trk>
          <trkseg><trkpt lat="3" lon="179.9"/><trkpt lat="4" lon="-179.9"/></trkseg>
          <trkseg><trkpt lat="6" lon="-179.9"/><trkpt lat="7" lon="-179.8"/></trkseg>
        </trk></gpx>
        """.write(to: url, atomically: true, encoding: .utf8)
        let track = try ProjectGPXTrack(contentsOf: url)
        let overlays = GPXTrackPolyline.overlays(for: track)
        XCTAssertEqual(overlays.map(\.pointCount), [2, 2, 2])
        XCTAssertTrue(overlays.allSatisfy { $0.boundingMapRect.width < MKMapRect.world.width / 360 })
        XCTAssertEqual(overlays.first?.points()[1].coordinate.latitude ?? 0, 3.5, accuracy: 0.000001)
    }
}
