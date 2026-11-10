import IsoniqueCore
import XCTest
@testable import Isonique

final class GPXLocationTests: XCTestCase {
    @MainActor
    func testPreviewCancelApplyAndReopenWithOfflineOriginalAndOneUndoStep() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueGPX-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let libraryRoot = root.appendingPathComponent("Library")
        let workspace = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        let url = root.appendingPathComponent("Track.gpx")
        try londonTrack.write(to: url, atomically: true, encoding: .utf8)
        let track = try GPXTrack(contentsOf: url)
        let original = root.appendingPathComponent("Exact.jpg")
        let originalBytes = Data("Original fixture bytes".utf8)
        try originalBytes.write(to: original)
        var exact = photo("Exact.jpg", date: "2026:07:04 12:30:00")
        exact.referencedPath = original.path
        exact.locationOverride = .assigned(try XCTUnwrap(GPSCoordinates(latitude: 1, longitude: 2)))
        var middle = photo("Middle.jpg", date: "2026:07:04 12:30:05")
        middle.referencedPath = root.appendingPathComponent("Offline.jpg").path
        let unchecked = photo("Unchecked.jpg", date: middle.captureDate)
        let missing = photo("Missing time.jpg", date: "")
        let late = photo("Outside the track.jpg", date: "2026:07:04 12:32:00")
        let unrelated = photo("Unselected.jpg", date: exact.captureDate)
        var library = workspace.library
        library.photos = [exact, middle, unchecked, missing, late, unrelated]
        var album = Collection(name: "Track matches")
        var rule = SmartAlbumRule()
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .gpsLocation, comparison: .withinRadius,
                                              gpsRadius: GPSRadiusRule(latitude: "51.5", longitude: "0", kilometres: "100"))]
        rule.query = query
        album.rule = rule
        library.albums = [album]
        XCTAssertTrue(workspace.commit(library))
        workspace.batchMode = true
        workspace.batchSelection = [exact.id, middle.id, unchecked.id, missing.id, late.id]
        XCTAssertEqual(workspace.isOriginalAvailable(middle), false)
        let catalogue = libraryRoot.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let settings = GPXLocationEdit.Settings(timeZone: try XCTUnwrap(TimeZone(identifier: "Europe/London")), maximumGap: 15)

        workspace.openGPXLocationEditor(url: url)
        let edit = try XCTUnwrap(workspace.gpxLocationEditor)
        let preview = try edit.preview(track: track, settings: settings)
        XCTAssertEqual(Set(preview.rows.map(\.id)), workspace.batchSelection)
        XCTAssertEqual(Set(preview.changes(excluding: [unchecked.id]).map(\.photoID)), [exact.id, middle.id])
        XCTAssertEqual(preview.rows.first { $0.id == exact.id }?.target.coordinates, exact.cataloguedLocation)
        guard case .invalidCaptureTime? = preview.rows.first(where: { $0.id == missing.id })?.result,
              case .noMatch? = preview.rows.first(where: { $0.id == late.id })?.result else {
            return XCTFail("Expected distinct results for missing times and unmatched times")
        }
        XCTAssertTrue(try edit.preview(track: track, settings: .init(timeZone: .gmt, maximumGap: 15))
            .changes(excluding: []).isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        workspace.gpxLocationEditor = nil
        XCTAssertFalse(workspace.applyGPXLocations(preview, excluding: []))
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertTrue(workspace.history.undo.isEmpty)

        workspace.openGPXLocationEditor(url: url)
        let reopenedReview = try XCTUnwrap(workspace.gpxLocationEditor)
        XCTAssertTrue(workspace.applyGPXLocations(try reopenedReview.preview(track: track, settings: settings),
                                                   excluding: [unchecked.id]))
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)

        let reopened = Workspace(libraryRoot: libraryRoot, preferences: preferences)
        XCTAssertNil(reopened.error)
        reopened.scope = "album:\(album.id)"
        XCTAssertEqual(Set(reopened.photos.map(\.id)), [exact.id, middle.id])
        reopened.choosePresentation(.places)
        let points = try [XCTUnwrap(GPSCoordinates(latitude: 51, longitude: -0.2)),
                          XCTUnwrap(GPSCoordinates(latitude: 51.5, longitude: 0))]
        XCTAssertEqual(Set(PhotoPlace.grouped(reopened.photos).map(\.id)), Set(points))
        reopened.undoEdit()
        XCTAssertTrue(reopened.photos.isEmpty)
        XCTAssertEqual(reopened.library.photos.first { $0.id == exact.id }?.locationOverride, exact.locationOverride)
        reopened.redoEdit()
        XCTAssertEqual(Set(reopened.photos.map(\.id)), [exact.id, middle.id])
        XCTAssertEqual(try Data(contentsOf: original), originalBytes)
    }

    @MainActor
    func testApplyRejectsChangedSelectionAndCaptureTime() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueGPX-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let first = photo("First.jpg", date: "2026:07:04 11:30:00")
        let second = photo("Second.jpg", date: first.captureDate)
        var library = workspace.library
        library.photos = [first, second]
        XCTAssertTrue(workspace.commit(library))
        workspace.selection = first.id
        workspace.openGPXLocationEditor(url: root.appendingPathComponent("Track.gpx"))
        let edit = try XCTUnwrap(workspace.gpxLocationEditor)
        let track = try GPXTrack(data: Data(londonTrack.utf8))
        let preview = try edit.preview(track: track, settings: .init(timeZone: .gmt, maximumGap: 15))
        XCTAssertEqual(preview.changes(excluding: []).map(\.photoID), [first.id])
        workspace.selection = second.id
        XCTAssertFalse(workspace.applyGPXLocations(preview, excluding: []))
        workspace.selection = first.id
        workspace.error = nil
        var updated = workspace.library
        updated.photos[0].captureDate = "2026:07:04 11:30:05"
        XCTAssertTrue(workspace.commit(updated))
        let catalogue = root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        XCTAssertFalse(workspace.applyGPXLocations(preview, excluding: []))
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertTrue(workspace.history.undo.isEmpty)
    }

    func testDaylightSavingGapAndRepeatedTimesAreSkippedUnlessOffsetIsExplicit() throws {
        let track = try GPXTrack(data: Data("""
            <gpx><trk><trkseg>
              <trkpt lat="51" lon="0"><time>2026-03-29T00:30:00Z</time></trkpt>
              <trkpt lat="52" lon="0"><time>2026-10-25T00:30:00Z</time></trkpt>
              <trkpt lat="53" lon="0"><time>2026-10-25T01:30:00Z</time></trkpt>
            </trkseg></trk></gpx>
            """.utf8))
        let spring = photo("Spring.jpg", date: "2026:03:29 01:30:00")
        let autumn = photo("Autumn.jpg", date: "2026:10:25 01:30:00")
        let root = FileManager.default.temporaryDirectory
        let edit = GPXLocationEdit(url: root, libraryRoot: root, targets: [spring, autumn].map(GPXLocationEdit.Target.init))
        let london = try XCTUnwrap(TimeZone(identifier: "Europe/London"))
        let preview = try edit.preview(track: track, settings: .init(timeZone: london, maximumGap: 120))
        for row in preview.rows {
            guard case .invalidCaptureTime = row.result else { return XCTFail("Expected an invalid local time") }
        }
        let fixed = try XCTUnwrap(TimeZone(identifier: "UTC+01:00"))
        let explicit = try edit.preview(track: track, settings: .init(timeZone: fixed, maximumGap: 120))
        XCTAssertEqual(explicit.changes(excluding: []).count, 2)
        guard case .matched(let autumnMatch) = explicit.rows[1].result else { return XCTFail("Expected an exact match") }
        XCTAssertEqual(autumnMatch.coordinates.latitude, 52)
    }

    private var londonTrack: String {
        """
        <gpx xmlns="http://www.topografix.com/GPX/1/1"><trk><trkseg>
          <trkpt lat="51" lon="-0.2"><time>2026-07-04T11:30:00Z</time></trkpt>
          <trkpt lat="52" lon="0.2"><time>2026-07-04T11:30:10Z</time></trkpt>
        </trkseg></trk></gpx>
        """
    }

    private func photo(_ name: String, date: String) -> Photo {
        Photo(filename: name, originalName: name, projectID: nil, width: 32, height: 24,
              camera: "", captureDate: date, sha256: name)
    }
}
