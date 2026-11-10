import IsoniqueCore
import XCTest

final class ProjectGPXTrackTests: XCTestCase {
    func testGeometryUsesUntimedTrackPointsAndKeepsSegmentBreaks() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Walk.gpx")
        try """
        <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1">
          <g:wpt lat="50" lon="0"/>
          <g:rte><g:rtept lat="50" lon="0"/><g:rtept lat="51" lon="0"/></g:rte>
          <g:trk>
            <g:trkseg>
              <g:trkpt lat="1" lon="1"><g:time>invalid</g:time></g:trkpt>
              <g:trkpt lat="1" lon="1"/>
              <g:trkpt lat="2" lon="2"/>
              <g:trkpt lat="91" lon="0"/>
              <g:trkpt lat="3" lon="3"/>
              <g:trkpt lat="4" lon="4"/>
            </g:trkseg>
            <g:trkseg><g:trkpt lat="5" lon="5"/><g:trkpt lat="6" lon="6"/></g:trkseg>
            <g:trkseg><g:trkpt lat="7" lon="7"/></g:trkseg>
          </g:trk>
        </g:gpx>
        """.write(to: url, atomically: true, encoding: .utf8)
        let track = try ProjectGPXTrack(contentsOf: url)
        XCTAssertEqual(track.name, "Walk")
        XCTAssertEqual(track.segments.map { $0.map(\.latitude) }, [[1, 2], [3, 4], [5, 6]])
        XCTAssertTrue(track.isVisible)
        XCTAssertThrowsError(try GPXTrack(contentsOf: url)) {
            XCTAssertEqual($0 as? GPXTrack.ReadError, .noTimedPoints)
        }

        try "<gpx><trk><trkseg><trkpt lat='1' lon='1'/></trkseg></trk></gpx>"
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try ProjectGPXTrack(contentsOf: url)) {
            XCTAssertEqual($0 as? GPXTrack.ReadError, .noDrawableSegments)
        }
    }

    func testProjectLibraryExportAndImportKeepTheTrackWithItsProject() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let repository = try LibraryRepository(root: root.appendingPathComponent("Library"))
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Walk.gpx")
        try """
        <gpx xmlns="http://www.topografix.com/GPX/1/0"><trk><trkseg>
          <trkpt lat="1" lon="2"/><trkpt lat="3" lon="4"/>
        </trkseg></trk></gpx>
        """.write(to: url, atomically: true, encoding: .utf8)
        var library = try repository.openOrCreateCatalogue()
        let project = Collection(name: "Walk")
        let otherProject = Collection(name: "Another walk")
        library.projects = [project, otherProject]
        library.version = 16
        XCTAssertEqual(try repository.save(library).version, 16)
        library = try repository.load()
        XCTAssertNil(library.projects[0].gpxTracks)
        let track = try ProjectGPXTrack(contentsOf: url)
        XCTAssertTrue(library.addProjectGPXTrack(track, to: project.id))
        XCTAssertTrue(library.setProjectGPXTrackVisibility(false, trackID: track.id, in: project.id))
        XCTAssertFalse(library.removeProjectGPXTrack(track.id, from: otherProject.id))
        XCTAssertEqual(try repository.save(library).version, 17)

        let export = root.appendingPathComponent("Export")
        XCTAssertEqual(try LibraryBackup.exportProject(project.id, from: repository, to: export), 0)
        let exported = try LibraryRepository(root: export).load()
        let savedTracks = try repository.load().projects[0].gpxTracks
        XCTAssertEqual(exported.projects.map(\.id), [project.id])
        XCTAssertEqual(exported.projects[0].gpxTracks, savedTracks)
        XCTAssertEqual(savedTracks?.first?.isVisible, false)

        let imported = try await repository.importProjectLibrary(from: export)
        XCTAssertNotEqual(imported.project.id, project.id)
        XCTAssertEqual(imported.project.gpxTracks, savedTracks)
        var draft = imported.library
        XCTAssertTrue(draft.removeProjectGPXTrack(track.id, from: imported.project.id))
        let saved = try repository.save(draft)
        XCTAssertEqual(saved.projects.first { $0.id == project.id }?.gpxTracks, savedTracks)
        XCTAssertNil(saved.projects.first { $0.id == imported.project.id }?.gpxTracks)
    }
}
