import IsoniqueCore
import XCTest

final class GPXTrackTests: XCTestCase {
    func testNamespacedTrackTimestampsAndFractionalInterpolation() throws {
        let track = try read("""
            <g:gpx xmlns:g="http://www.topografix.com/GPX/1/1" xmlns:ext="urn:example" version="1.1">
              <g:wpt lat="1" lon="2"><g:time>2026-07-04T11:30:01Z</g:time></g:wpt>
              <g:trk><g:trkseg>
                <g:trkpt lat="50" lon="-1"><g:time>2026-07-04T12:30:00.250+01:00</g:time></g:trkpt>
                <g:trkpt lat="53" lon="2"><g:time><![CDATA[2026-07-04T11:30:01.750Z]]></g:time></g:trkpt>
                <ext:trkpt lat="1" lon="2"><g:time>2026-07-04T11:30:02Z</g:time></ext:trkpt>
              </g:trkseg></g:trk>
            </g:gpx>
            """)
        let start = date(0).addingTimeInterval(0.25)
        let exact = try XCTUnwrap(track.match(at: start, maximumGap: 0))
        XCTAssertEqual(exact.method, .exact)
        XCTAssertEqual(exact.coordinates.latitude, 50)
        let middle = try XCTUnwrap(track.match(at: date(1), maximumGap: 1.5))
        XCTAssertEqual(middle.method, .interpolated)
        XCTAssertEqual(middle.coordinates.latitude, 51.5, accuracy: 0.000001)
        XCTAssertEqual(middle.coordinates.longitude, 0.5, accuracy: 0.000001)
        XCTAssertNil(track.match(at: date(1), maximumGap: 1.49))
        XCTAssertNil(track.match(at: date(0), maximumGap: 900))
        XCTAssertNil(track.match(at: date(2), maximumGap: 900))
    }

    func testNeverInterpolatesAcrossSegmentsInvalidPointsOrClockResets() throws {
        let track = try read("""
            <gpx xmlns="http://www.topografix.com/GPX/1/0" version="1.0"><trk>
              <trkseg>
                <trkpt lat="0" lon="0"><time>2026-07-04T11:30:00Z</time></trkpt>
                <trkpt lat="0" lon="0"/>
                <trkpt lat="0" lon="0"><time>2026-07-04T11:30:10Z</time></trkpt>
              </trkseg>
              <trkseg>
                <trkpt lat="1" lon="1"><time>2026-07-04T11:30:20Z</time></trkpt>
                <trkpt lat="100" lon="1"><time>2026-07-04T11:30:25Z</time></trkpt>
                <trkpt lat="1" lon="1"><time>2026-07-04T11:30:30Z</time></trkpt>
                <trkpt lat="2" lon="2"><time>2026-07-04T11:30:15Z</time></trkpt>
              </trkseg>
            </trk></gpx>
            """)
        for seconds in [5, 12, 17, 25] {
            XCTAssertNil(track.match(at: date(seconds), maximumGap: 900))
        }
        XCTAssertEqual(track.match(at: date(15), maximumGap: 0)?.coordinates.latitude, 2)
    }

    func testDateLineAndOverlappingFixes() throws {
        let track = try read("""
            <gpx><trk>
              <trkseg>
                <trkpt lat="0" lon="179"><time>2026-07-04T11:30:00Z</time></trkpt>
                <trkpt lat="2" lon="-179"><time>2026-07-04T11:30:10Z</time></trkpt>
              </trkseg>
              <trkseg>
                <trkpt lat="5" lon="5"><time>2026-07-04T11:30:06Z</time></trkpt>
                <trkpt lat="6" lon="6"><time>2026-07-04T11:30:10Z</time></trkpt>
              </trkseg>
            </trk></gpx>
            """)
        XCTAssertEqual(track.match(at: date(5), maximumGap: 10)?.coordinates.longitude, 180)
        XCTAssertEqual(track.match(at: date(6), maximumGap: 10)?.method, .exact)
        XCTAssertEqual(track.match(at: date(6), maximumGap: 10)?.coordinates.latitude, 5)
        XCTAssertNil(track.match(at: date(8), maximumGap: 10))
        XCTAssertNil(track.match(at: date(10), maximumGap: 10))
    }

    func testRejectsMalformedFilesAndFilesWithoutTimedTrackPoints() throws {
        let point = "<trkpt lat='1' lon='2'><time>2026-07-04T11:30:00Z</time></trkpt>"
        for input in ["<kml/>", "<gpx><trk><trkseg>\(point)</trkseg></gpx>"] {
            XCTAssertThrowsError(try read(input)) { XCTAssertEqual($0 as? GPXTrack.ReadError, .invalidTrack) }
        }
        let untimed = """
            <gpx><rte><rtept lat="1" lon="2"><time>2026-07-04T11:30:00Z</time></rtept></rte>
            <trk><trkseg>
              <trkpt lat="0" lon="0"><time>2026-07-04T11:30:00</time></trkpt>
              <trkpt lat="0" lon="0"><time>2026-02-30T11:30:00Z</time></trkpt>
              <trkpt lat="nan" lon="0"><time>2026-07-04T11:30:00Z</time></trkpt>
            </trkseg></trk></gpx>
            """
        XCTAssertThrowsError(try read(untimed)) { XCTAssertEqual($0 as? GPXTrack.ReadError, .noTimedPoints) }
    }

    func testCancelledReadThrowsCancellation() async {
        let job = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try GPXTrack(data: Data("<gpx/>".utf8))
        }
        do {
            _ = try await job.value
            XCTFail("Expected the cancelled read to throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    private func read(_ xml: String) throws -> GPXTrack { try GPXTrack(data: Data(xml.utf8)) }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: 1_783_164_600 + TimeInterval(seconds))
    }
}
