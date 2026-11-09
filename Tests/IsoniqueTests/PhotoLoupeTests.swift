import CoreGraphics
import XCTest
@testable import Isonique

final class PhotoLoupeTests: XCTestCase {
    func testRegionKeepsTargetAtEdgesAndSupportsTinyImages() {
        let center = LoupeSample(point: CGPoint(x: 0.5, y: 0.5), width: 600, height: 320, span: 36)
        XCTAssertEqual(center.x, 300)
        XCTAssertEqual(center.y, 160)
        XCTAssertEqual(center.region, CGRect(x: 282, y: 142, width: 36, height: 36))
        let corner = LoupeSample(point: CGPoint(x: 1, y: 1), width: 600, height: 320, span: 18)
        XCTAssertEqual(corner.x, 599)
        XCTAssertEqual(corner.y, 319)
        XCTAssertEqual(corner.region, CGRect(x: 582, y: 302, width: 18, height: 18))
        let tiny = LoupeSample(point: .zero, width: 2, height: 1, span: 72)
        XCTAssertEqual(tiny.region, CGRect(x: 0, y: 0, width: 2, height: 1))
    }

    func testReadsTopLeftCoordinatesAndStraightAlpha() throws {
        let bytes: [UInt8] = [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 64, 32, 0, 128]
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let colorSpace = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        let image = try XCTUnwrap(CGImage(width: 2, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 8,
                                          space: colorSpace, bitmapInfo: info, provider: provider, decode: nil,
                                          shouldInterpolate: false, intent: .defaultIntent))
        let topLeft = LoupeSample(point: .zero, width: 2, height: 2, span: 2)
        let bottomLeft = LoupeSample(point: CGPoint(x: 0, y: 0.9), width: 2, height: 2, span: 2)
        let bottomRight = LoupeSample(point: CGPoint(x: 0.9, y: 0.9), width: 2, height: 2, span: 2)
        XCTAssertEqual(topLeft.rgba(in: image), [255, 0, 0, 255])
        XCTAssertEqual(bottomLeft.rgba(in: image), [0, 0, 255, 255])
        XCTAssertEqual(bottomRight.rgba(in: image), [128, 64, 0, 128])
    }
}
