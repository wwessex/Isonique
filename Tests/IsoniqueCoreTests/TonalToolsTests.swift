import XCTest
import CoreGraphics
@testable import IsoniqueCore

final class TonalToolsTests: XCTestCase {
    func testNeutralLegacyAndPersistence() throws {
        let neutral = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        for input in 0...255 { XCTAssertEqual(TonalTools.map(Double(input) / 255, adjustments: neutral), Double(input) / 255, accuracy: 1e-12) }
        var settings = neutral; settings.blackPoint = 0.1; settings.whitePoint = 0.9; settings.gamma = 1.5; settings.curveMidtones = 0.6
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertEqual(settings.stamping(onto: neutral, groups: [.tone]), settings)
        XCTAssertEqual(settings.stamping(onto: neutral, groups: [.basic]), neutral)
    }
    func testLevelsClippingGammaAndCurve() {
        var settings = Adjustments(); settings.blackPoint = 0.2; settings.whitePoint = 0.8
        XCTAssertEqual(TonalTools.map(0.1, adjustments: settings), 0)
        XCTAssertEqual(TonalTools.map(0.9, adjustments: settings), 1)
        XCTAssertEqual(TonalTools.map(0.5, adjustments: settings), 0.5, accuracy: 1e-12)
        settings = Adjustments(); settings.gamma = 2
        XCTAssertEqual(TonalTools.map(0.25, adjustments: settings), 0.5, accuracy: 1e-12)
        settings = Adjustments(); settings.curveMidtones = 0.75
        XCTAssertEqual(TonalTools.map(0.5, adjustments: settings), 0.75)
        settings.blackPoint = .nan; settings.whitePoint = -.infinity; settings.gamma = 0
        XCTAssertTrue(TonalTools.map(0.5, adjustments: settings).isFinite)
    }
    func testHistogramAndPixelsShareToneTable() throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 1, bitsPerComponent: 8, bytesPerRow: 16, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        let bytes = try XCTUnwrap(context.data).bindMemory(to: UInt8.self, capacity: 16)
        for (index, value) in [0, 64, 128, 255].enumerated() { for channel in 0..<3 { bytes[index * 4 + channel] = UInt8(value) }; bytes[index * 4 + 3] = 255 }
        let image = try XCTUnwrap(context.makeImage())
        let histogram = try TonalTools.histogram(image)
        XCTAssertEqual(histogram.reduce(0, +), 4)
        for value in [0, 64, 128, 255] { XCTAssertEqual(histogram[value], 1) }
        var settings = Adjustments(); settings.blackPoint = 0.3
        let output = try TonalTools.applying(image, table: (0...255).map { TonalTools.map(Double($0) / 255, adjustments: settings) })
        let edited = try TonalTools.histogram(output)
        XCTAssertEqual(edited[0], 2); XCTAssertEqual(edited[255], 1)
    }
    func testHistogramChannelsCountStraightRGBAndReflectCurveEdits() throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: 3, height: 1, bitsPerComponent: 8,
                                             bytesPerRow: 12, space: space, bitmapInfo: info))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        let samples: [UInt8] = [200, 100, 0, 255, 0, 64, 128, 128, 0, 0, 0, 0]
        for (index, value) in samples.enumerated() { bytes[index] = value }
        let image = try XCTUnwrap(context.makeImage())
        let histogram = try TonalTools.histogramChannels(image)
        for bins in [histogram.luminance, histogram.red, histogram.green, histogram.blue] {
            XCTAssertEqual(bins.count, 256)
            XCTAssertEqual(bins.reduce(0, +), 2)
        }
        XCTAssertEqual(histogram.red[200], 1)
        XCTAssertEqual(histogram.red[0], 1)
        XCTAssertEqual(histogram.green[100], 1)
        XCTAssertEqual(histogram.green[128], 1)
        XCTAssertEqual(histogram.blue[255], 1)
        XCTAssertEqual(histogram.luminance[114], 1)
        XCTAssertEqual(histogram.luminance[110], 1)
        var settings = Adjustments()
        var curve = ChannelCurve.identity
        curve.insertPoint(input: 200, output: 180)
        settings.setCurve(curve, for: .red)
        let adjusted = try TonalTools.applying(image, table: (0...255).map { Double($0) / 255 },
                                              curves: settings.channelCurves)
        let edited = try TonalTools.histogramChannels(adjusted)
        XCTAssertEqual(edited.red[180], 1)
        XCTAssertEqual(edited.red[200], 0)
        XCTAssertEqual(edited.green, histogram.green)
        XCTAssertEqual(edited.blue, histogram.blue)
    }
    func testAutoStackGapsInvalidDatesAndExistingStacks() {
        func photo(_ date: String) -> Photo { Photo(filename: "a", originalName: "a", projectID: nil, width: 1, height: 1, camera: "", captureDate: date, sha256: "hash") }
        let a = photo("2026:11:09 12:00:00"), b = photo("2026:11:09 12:00:02"), c = photo("2026:11:09 12:00:04"), d = photo("2026:11:09 12:01:00")
        var stacked = photo("2026:11:09 12:00:01"); stacked.stackID = UUID()
        let input = [d, c, b, a, photo(""), photo("bad"), stacked]
        XCTAssertEqual(AutoStack.groups(input, seconds: 2), [[a.id, b.id, c.id]])
        XCTAssertTrue(AutoStack.groups(input, seconds: 1).isEmpty)
        XCTAssertTrue(AutoStack.groups(input, seconds: .nan).isEmpty)
    }
}
