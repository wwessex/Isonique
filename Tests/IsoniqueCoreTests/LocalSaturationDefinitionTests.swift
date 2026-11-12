import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class LocalSaturationDefinitionTests: XCTestCase {
    func testNeutralIndependentAndOverlappingSaturationAndDefinition() throws {
        try withFixture { source, _ in
            let neutral = try Renderer.render(source, adjustments: Adjustments())
            let point = BrushPoint(x: 0.5, y: 0.5)
            let saturationStroke = stroke(.saturation, point: point)
            let definitionStroke = stroke(.definition, point: point)

            var zeroOpacity = Adjustments()
            zeroOpacity.localBrushes = [saturationStroke, definitionStroke]
            zeroOpacity.localBrushMaskSettings = [
                .saturation: LocalBrushMaskSettings(opacity: 0),
                .definition: LocalBrushMaskSettings(opacity: 0),
            ]
            XCTAssertEqual(try pixels(Renderer.render(source, adjustments: zeroOpacity)), try pixels(neutral))

            var saturation = Adjustments()
            saturation.localBrushes = [saturationStroke]
            let saturated = try Renderer.render(source, adjustments: saturation)
            var definition = Adjustments()
            definition.localBrushes = [definitionStroke]
            let defined = try Renderer.render(source, adjustments: definition)
            var both = Adjustments()
            both.localBrushes = [saturationStroke, definitionStroke]
            let overlapped = try Renderer.render(source, adjustments: both)

            let x = neutral.width / 2, y = neutral.height / 2
            XCTAssertGreaterThan(chroma(try pixel(saturated, x: x, y: y)),
                                 chroma(try pixel(neutral, x: x, y: y)) + 20)
            XCTAssertEqual(chroma(try pixel(defined, x: x, y: y)),
                           chroma(try pixel(neutral, x: x, y: y)), accuracy: 2)
            XCTAssertGreaterThan(try localContrast(defined, x: x, y: y),
                                 try localContrast(neutral, x: x, y: y) + 5)
            XCTAssertGreaterThan(chroma(try pixel(overlapped, x: x, y: y)),
                                 chroma(try pixel(defined, x: x, y: y)) + 20)
            XCTAssertGreaterThan(try localContrast(overlapped, x: x, y: y),
                                 try localContrast(saturated, x: x, y: y) + 5)
            XCTAssertNotEqual(try pixels(overlapped), try pixels(saturated))
            XCTAssertNotEqual(try pixels(overlapped), try pixels(defined))
        }
    }

    func testNewMasksProtectEdgesAndKeepEraseInvertAndOpacityIndependent() throws {
        let width = 100, height = 60
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = x < width / 2 ? 40 : 215
                let offset = (y * width + x) * 4
                pixels[offset] = value; pixels[offset + 1] = value; pixels[offset + 2] = value
            }
        }
        let edgeMap = pixels.withUnsafeBufferPointer {
            LocalBrushEdgeMap(pixels: $0.baseAddress!, width: width, height: height)
        }
        let saturation = LocalBrushStroke(adjustment: .saturation, radius: 0.25, softness: 0,
            strength: 1, edgeAware: true, points: [BrushPoint(x: 0.4, y: 0.5)])
        let definition = LocalBrushStroke(adjustment: .definition, radius: 0.25, softness: 0,
            strength: 1, edgeAware: true, points: [BrushPoint(x: 0.6, y: 0.5)])
        let erase = LocalBrushStroke(adjustment: .saturation, erasing: true, radius: 0.08,
            softness: 0, strength: 1, edgeAware: true, points: [BrushPoint(x: 0.4, y: 0.5)])
        let mask = try XCTUnwrap(LocalAdjustmentMask(strokes: [saturation, definition, erase], settings: [
            .saturation: LocalBrushMaskSettings(opacity: 0.5),
            .definition: LocalBrushMaskSettings(opacity: 0.25, inverted: true),
        ], sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))

        XCTAssertEqual(coverage(mask, .saturation, x: 40, y: 30, width: width, height: height), 0,
                       accuracy: 0.0001)
        XCTAssertEqual(coverage(mask, .saturation, x: 52, y: 30, width: width, height: height), 0,
                       accuracy: 0.0001, "Edge protection must not cross to the bright side")
        XCTAssertGreaterThan(coverage(mask, .saturation, x: 30, y: 30, width: width, height: height), 0.49)
        XCTAssertEqual(coverage(mask, .definition, x: 60, y: 30, width: width, height: height), 0,
                       accuracy: 0.0001)
        XCTAssertEqual(coverage(mask, .definition, x: 30, y: 30, width: width, height: height), 0.25,
                       accuracy: 0.0001, "Inversion and opacity apply only to the Definition mask")
    }

    func testExtendedBrushRecipeUsesFormat28AndRoundTripsWithStamping() throws {
        var library = Library()
        var photo = Photo(filename: "source.png", originalName: "source.png", projectID: nil,
                          width: 100, height: 60, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.localBrushes = [stroke(.saturation, point: BrushPoint(x: 0.3, y: 0.4)),
                                          stroke(.definition, point: BrushPoint(x: 0.7, y: 0.6))]
        photo.adjustments.localBrushMaskSettings[.definition] = LocalBrushMaskSettings(opacity: 0.6,
                                                                                        inverted: true)
        library.photos = [photo]
        XCTAssertThrowsError(try library.validateSchema())
        library.upgradeForExtendedLocalBrushes()
        XCTAssertEqual(library.version, 28)
        XCTAssertNoThrow(try library.validateSchema())

        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded.photos[0].adjustments, photo.adjustments)
        let stamped = photo.adjustments.stamping(onto: Adjustments(), groups: [.localBrush])
        XCTAssertEqual(stamped.localBrushes, photo.adjustments.localBrushes)
        XCTAssertEqual(stamped.localBrushMaskSettings, photo.adjustments.localBrushMaskSettings)
        XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.basic]).localBrushes, [])
    }

    private func stroke(_ adjustment: LocalBrushAdjustment, point: BrushPoint) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: adjustment, radius: 0.24, softness: 0.2,
                         strength: 1, points: [point])
    }

    private func coverage(_ mask: LocalAdjustmentMask, _ adjustment: LocalBrushAdjustment,
                          x: Int, y: Int, width: Int, height: Int) -> Double {
        mask.coverage(for: adjustment, x: x, y: y, imageWidth: width, imageHeight: height)
    }

    private func withFixture(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueLocalEffects-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Texture.png")
        let width = 160, height = 100
        var values = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let texture = (x + y).isMultiple(of: 2) ? -8 : 8
                let offset = (y * width + x) * 4
                values[offset] = UInt8(78 + texture)
                values[offset + 1] = UInt8(112 + texture)
                values[offset + 2] = UInt8(150 + texture)
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(values) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        try body(source, root)
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

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> (Double, Double, Double) {
        let values = try pixels(image), offset = (y * image.width + x) * 4
        return (Double(values[offset]), Double(values[offset + 1]), Double(values[offset + 2]))
    }

    private func chroma(_ pixel: (Double, Double, Double)) -> Double {
        max(pixel.0, pixel.1, pixel.2) - min(pixel.0, pixel.1, pixel.2)
    }

    private func localContrast(_ image: CGImage, x: Int, y: Int) throws -> Double {
        let left = try pixel(image, x: x - 1, y: y)
        let right = try pixel(image, x: x, y: y)
        func luminance(_ pixel: (Double, Double, Double)) -> Double {
            0.2126 * pixel.0 + 0.7152 * pixel.1 + 0.0722 * pixel.2
        }
        return abs(luminance(left) - luminance(right))
    }
}
