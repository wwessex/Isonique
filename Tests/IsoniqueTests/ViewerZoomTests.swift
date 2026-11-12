import XCTest
@testable import Isonique

final class ViewerZoomTests: XCTestCase {
    func testPinchBoundsFitTransitionAndStableGestureBase() {
        XCTAssertNil(ViewerZoom.magnified(from: nil, by: 0.5),
                     "Pinching inward while fitted must leave the image fitted")
        XCTAssertNil(ViewerZoom.magnified(from: nil, by: 1.02))
        XCTAssertEqual(ViewerZoom.magnified(from: nil, by: 1.25), 1.25)
        XCTAssertEqual(ViewerZoom.magnified(from: 1, by: 20), 8)
        XCTAssertEqual(ViewerZoom.magnified(from: 1, by: 0.22), 0.25)
        XCTAssertNil(ViewerZoom.magnified(from: 1, by: 0.19))
        XCTAssertEqual(ViewerZoom.magnified(from: 2, by: 1.5), 3,
                       "Every mid-gesture sample must remain relative to the captured start scale")
        XCTAssertEqual(ViewerZoom.magnified(from: 2, by: 1.75), 3.5)
        XCTAssertEqual(ViewerZoom.magnified(from: 2, by: .nan), 2)
    }

    func testFitButtonAndPercentageRemainCompatible() {
        XCTAssertEqual(ViewerZoom.toggled(nil), 1)
        XCTAssertNil(ViewerZoom.toggled(1))
        XCTAssertEqual(ViewerZoom.percentage(1), "100%")
        XCTAssertEqual(ViewerZoom.percentage(0.25), "25%")
        XCTAssertEqual(ViewerZoom.percentage(8), "800%")
    }
}
