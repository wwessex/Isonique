import XCTest
@testable import Isonique

final class ViewerZoomTests: XCTestCase {
    func testPinchBoundsFitTransitionAndStableGestureBase() throws {
        XCTAssertNil(ViewerZoom.magnified(from: nil, by: 0.5, fitScale: 0.2),
                     "Pinching inward while fitted must leave the image fitted")
        XCTAssertNil(ViewerZoom.magnified(from: nil, by: 1.004, fitScale: 0.2))
        XCTAssertEqual(try XCTUnwrap(ViewerZoom.magnified(from: nil, by: 1.01, fitScale: 0.2)),
                       0.202, accuracy: 0.000_001)
        XCTAssertEqual(ViewerZoom.magnified(from: 1, by: 20, fitScale: 0.2), 8)
        XCTAssertEqual(ViewerZoom.magnified(from: 1, by: 0.22, fitScale: 0.2), 0.22)
        XCTAssertNil(ViewerZoom.magnified(from: 1, by: 0.19, fitScale: 0.2))
        XCTAssertEqual(ViewerZoom.magnified(from: 2, by: 1.5, fitScale: 0.2), 3,
                       "Every mid-gesture sample must remain relative to the captured start scale")
        XCTAssertEqual(ViewerZoom.magnified(from: 2, by: 1.75, fitScale: 0.2), 3.5)
        XCTAssertEqual(ViewerZoom.magnified(from: 2, by: .nan, fitScale: 0.2), 2)
        XCTAssertEqual(ViewerZoom.fittedScale(viewportSize: CGSize(width: 1032, height: 532),
                                              imageSize: CGSize(width: 2000, height: 1000)), 0.5)
    }

    func testFitButtonAndPercentageRemainCompatible() {
        XCTAssertEqual(ViewerZoom.toggled(nil), 1)
        XCTAssertNil(ViewerZoom.toggled(1))
        XCTAssertEqual(ViewerZoom.percentage(1), "100%")
        XCTAssertEqual(ViewerZoom.percentage(0.25), "25%")
        XCTAssertEqual(ViewerZoom.percentage(0.05), "5%")
        XCTAssertEqual(ViewerZoom.percentage(8), "800%")
    }
}
