import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class LocalPolarizeHaloBrushTests: XCTestCase {
    func testPolarizeNeutralAndMaximumTargetCoolSaturatedPixels() throws {
        let source = try image(width: 120, height: 64) { x, _ in
            x < 60 ? (70, 135, 205) : (205, 135, 70)
        }
        let mask = try XCTUnwrap(LocalAdjustmentMask(strokes: [wideStroke(.polarize)],
            sourceWidth: source.width, sourceHeight: source.height))
        XCTAssertEqual(try pixels(Renderer.applyLocalPolarize(source,
            settings: LocalPolarizeSettings(intensity: 0), mask: mask)), try pixels(source))

        let input = try pixels(source)
        let output = try pixels(Renderer.applyLocalPolarize(source,
            settings: LocalPolarizeSettings(intensity: 1), mask: mask))
        let blueBefore = pixel(input, x: 30, y: 32, width: 120)
        let blueAfter = pixel(output, x: 30, y: 32, width: 120)
        XCTAssertLessThan(luminance(blueAfter), luminance(blueBefore))
        XCTAssertGreaterThan(blueAfter.blue - blueAfter.red, blueBefore.blue - blueBefore.red)
        XCTAssertEqual(pixel(output, x: 90, y: 32, width: 120),
                       pixel(input, x: 90, y: 32, width: 120),
                       "Warm colours outside the polarizing range must remain neutral")

        let boundary = try image(width: 120, height: 64) { x, _ in
            x < 60 ? (45, 45, 45) : (215, 215, 215)
        }
        let boundaryPixels = try pixels(boundary)
        let edgeMap = boundaryPixels.withUnsafeBufferPointer {
            LocalBrushEdgeMap(pixels: $0.baseAddress!, width: 120, height: 64)
        }
        let protectedMask = try XCTUnwrap(LocalAdjustmentMask(strokes: [LocalBrushStroke(
            adjustment: .polarize, radius: 0.2, softness: 0, strength: 1, edgeAware: true,
            points: [BrushPoint(x: 0.45, y: 0.5)])], sourceWidth: 120, sourceHeight: 64,
            edgeMap: edgeMap))
        XCTAssertGreaterThan(protectedMask.coverage(for: .polarize, x: 52, y: 32,
            imageWidth: 120, imageHeight: 64), 0.9)
        XCTAssertEqual(protectedMask.coverage(for: .polarize, x: 64, y: 32,
            imageWidth: 120, imageHeight: 64), 0, accuracy: 0.0001)
    }

    func testHaloReductionNeutralFlatFieldRadiusAndEdgeClipping() throws {
        let flat = try image(width: 120, height: 64) { _, _ in (128, 128, 128) }
        let fullMask = try XCTUnwrap(LocalAdjustmentMask(strokes: [wideStroke(.haloReduction)],
            sourceWidth: flat.width, sourceHeight: flat.height))
        XCTAssertEqual(try pixels(Renderer.applyLocalHaloReduction(flat,
            settings: LocalHaloReductionSettings(amount: 1, radius: 0.08), mask: fullMask)),
            try pixels(flat), "A flat field must remain unchanged")

        let source = try haloFixture()
        let neutral = try Renderer.applyLocalHaloReduction(source,
            settings: LocalHaloReductionSettings(amount: 0, radius: 0.02), mask: fullMask)
        XCTAssertEqual(try pixels(neutral), try pixels(source))
        let input = try pixels(source)
        let small = try pixels(Renderer.applyLocalHaloReduction(source,
            settings: LocalHaloReductionSettings(amount: 1, radius: 0.01), mask: fullMask))
        let large = try pixels(Renderer.applyLocalHaloReduction(source,
            settings: LocalHaloReductionSettings(amount: 1, radius: 0.06), mask: fullMask))
        XCTAssertLessThan(pixel(small, x: 60, y: 32, width: 120).red,
                          pixel(input, x: 60, y: 32, width: 120).red)
        XCTAssertGreaterThan(pixel(small, x: 59, y: 32, width: 120).red,
                             pixel(input, x: 59, y: 32, width: 120).red)
        XCTAssertNotEqual(small, large, "Radius must change the sampled halo neighbourhood")

        let edgeMask = try XCTUnwrap(LocalAdjustmentMask(strokes: [LocalBrushStroke(
            adjustment: .haloReduction, radius: 0.08, softness: 0, strength: 1,
            points: [BrushPoint(x: 0, y: 0), BrushPoint(x: 1, y: 1)])],
            sourceWidth: source.width, sourceHeight: source.height))
        let clipped = try Renderer.applyLocalHaloReduction(source,
            settings: LocalHaloReductionSettings(amount: 1, radius: 0.08), mask: edgeMask)
        XCTAssertEqual(clipped.width, source.width)
        XCTAssertEqual(clipped.height, source.height)
    }

    func testSameTypeInstancesCompositeInDisplayedOrder() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniquePolarizeHaloOrder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Halos.png")
        try write(try haloFixture(), to: source)
        let first = LocalBrushInstance(name: "Tight", adjustment: .haloReduction,
            strokes: [wideStroke(.haloReduction)],
            haloReductionSettings: LocalHaloReductionSettings(amount: 1, radius: 0.01))
        let second = LocalBrushInstance(name: "Broad", adjustment: .haloReduction,
            strokes: [wideStroke(.haloReduction)],
            haloReductionSettings: LocalHaloReductionSettings(amount: 0.65, radius: 0.06))
        var recipe = Adjustments()
        recipe.localBrushInstances = [first, second]
        let tightThenBroad = try pixels(Renderer.render(source, adjustments: recipe))
        recipe.localBrushInstances = [second, first]
        let broadThenTight = try pixels(Renderer.render(source, adjustments: recipe))
        XCTAssertNotEqual(tightThenBroad, broadThenTight)
    }

    func testFormat33RoundTripsSettingsAndOlderInstancesKeepDefaults() throws {
        let id = UUID()
        let legacyJSON = """
        {"id":"\(id.uuidString)","name":"Old Tint","adjustment":"Tint","enabled":true}
        """
        let oldInstance = try JSONDecoder().decode(LocalBrushInstance.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(oldInstance.polarizeSettings, LocalPolarizeSettings())
        XCTAssertEqual(oldInstance.haloReductionSettings, LocalHaloReductionSettings())

        var photo = Photo(filename: "source.png", originalName: "source.png", projectID: nil,
                          width: 120, height: 64, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.localBrushInstances = [
            LocalBrushInstance(name: "Sky", adjustment: .polarize,
                strokes: [wideStroke(.polarize)], polarizeSettings: LocalPolarizeSettings(intensity: 0.82)),
            LocalBrushInstance(name: "Edges", adjustment: .haloReduction,
                strokes: [wideStroke(.haloReduction)],
                haloReductionSettings: LocalHaloReductionSettings(amount: 0.7, radius: 0.035)),
        ]
        var library = Library()
        library.version = 32
        library.photos = [photo]
        XCTAssertThrowsError(try library.validateSchema())
        library.upgradeForLocalPolarizeHalo()
        XCTAssertEqual(library.version, 33)
        XCTAssertNoThrow(try library.validateSchema())
        let reopened = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(reopened.photos[0].adjustments, photo.adjustments)
        XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.localBrush])
            .localBrushInstances, photo.adjustments.localBrushInstances)
    }

    private func wideStroke(_ adjustment: LocalBrushAdjustment) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: adjustment, radius: 0.25, softness: 0.25,
            strength: 1, edgeAware: false,
            points: [BrushPoint(x: 0.2, y: 0.5), BrushPoint(x: 0.5, y: 0.5),
                     BrushPoint(x: 0.8, y: 0.5)])
    }

    private func haloFixture() throws -> CGImage {
        try image(width: 120, height: 64) { x, _ in
            if x == 59 { return (0, 0, 0) }
            if x == 60 { return (255, 255, 255) }
            return x < 60 ? (45, 45, 45) : (205, 205, 205)
        }
    }

    private func image(width: Int, height: Int,
                       value: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4, channels = value(x, y)
                bytes[offset] = channels.0; bytes[offset + 1] = channels.1; bytes[offset + 2] = channels.2
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var values = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &values, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return values
    }

    private struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    private func pixel(_ values: [UInt8], x: Int, y: Int, width: Int) -> RGB {
        let offset = (y * width + x) * 4
        return RGB(red: Int(values[offset]), green: Int(values[offset + 1]),
                   blue: Int(values[offset + 2]))
    }

    private func luminance(_ pixel: RGB) -> Double {
        0.2126 * Double(pixel.red) + 0.7152 * Double(pixel.green) + 0.0722 * Double(pixel.blue)
    }
}
