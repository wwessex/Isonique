import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class TargetedColorTests: XCTestCase {
    func testNeutralBypassAndHueRangeWrapsAcrossRed() throws {
        let source = try image(colors: [rgba(hue: 359), rgba(hue: 1), rgba(hue: 180)])
        let neutral = TargetedColorAdjustment(name: "Red", centerHue: 0)
        XCTAssertEqual(try pixels(Renderer.applyTargetedColors(source, targets: [neutral])), try pixels(source))

        var shifted = neutral
        shifted.width = 8
        shifted.falloff = 0
        shifted.hueShift = 60
        let output = try Renderer.applyTargetedColors(source, targets: [shifted])
        XCTAssertEqual(try hue(output, x: 0), 59, accuracy: 2)
        XCTAssertEqual(try hue(output, x: 1), 61, accuracy: 2)
        XCTAssertEqual(try pixel(output, x: 2), try pixel(source, x: 2))
    }

    func testCoreWidthAndSmoothFalloffReachUnchangedBoundary() throws {
        let source = try image(colors: [rgba(hue: 0), rgba(hue: 15), rgba(hue: 30), rgba(hue: 40)])
        var target = TargetedColorAdjustment(name: "Red", centerHue: 0, width: 20, falloff: 20)
        target.saturation = -1
        let output = try Renderer.applyTargetedColors(source, targets: [target])
        XCTAssertEqual(try saturation(output, x: 0), 0, accuracy: 0.01)
        XCTAssertGreaterThan(try saturation(output, x: 1), 0.05)
        XCTAssertLessThan(try saturation(output, x: 1), 0.3)
        XCTAssertEqual(try pixel(output, x: 2), try pixel(source, x: 2))
        XCTAssertEqual(try pixel(output, x: 3), try pixel(source, x: 3))
        XCTAssertGreaterThan(target.weight(for: 15), 0)
        XCTAssertLessThan(target.weight(for: 15), 1)
        XCTAssertEqual(target.weight(for: 30), 0)
    }

    func testMultipleTargetsAdjustOnlyTheirOriginalHueRanges() throws {
        let source = try image(colors: [rgba(hue: 0), rgba(hue: 120), rgba(hue: 240)])
        var red = TargetedColorPreset.red.adjustment()
        red.width = 30
        red.falloff = 0
        red.saturation = -1
        var blue = TargetedColorPreset.blue.adjustment()
        blue.width = 30
        blue.falloff = 0
        blue.luminance = 0.5
        let output = try Renderer.applyTargetedColors(source, targets: [red, blue])
        XCTAssertEqual(try saturation(output, x: 0), 0, accuracy: 0.01)
        XCTAssertEqual(try pixel(output, x: 1), try pixel(source, x: 1))
        XCTAssertGreaterThan(try luminance(output, x: 2), try luminance(source, x: 2))
        XCTAssertEqual(try hue(output, x: 2), 240, accuracy: 2)
    }

    func testLoupeSamplingUsesGeometryAndRejectsAchromaticAndTransparentPixels() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Samples.png")
        let fixture = try image(width: 400, colors: [rgba(hue: 30), [128, 128, 128, 255], [0, 0, 0, 0], rgba(hue: 240)])
        try write(fixture, to: url)
        let orange = try XCTUnwrap(Renderer.sampleTargetedColor(url, adjustments: Adjustments(),
                                                                viewerPoint: CGPoint(x: 0.125, y: 0.5)))
        XCTAssertEqual(orange.hue, 30, accuracy: 1)
        XCTAssertNil(try Renderer.sampleTargetedColor(url, adjustments: Adjustments(),
                                                      viewerPoint: CGPoint(x: 0.375, y: 0.5)))
        XCTAssertNil(try Renderer.sampleTargetedColor(url, adjustments: Adjustments(),
                                                      viewerPoint: CGPoint(x: 0.625, y: 0.5)))
        var flipped = Adjustments()
        flipped.flipHorizontal = true
        let mapped = try XCTUnwrap(Renderer.sampleTargetedColor(url, adjustments: flipped,
                                                                viewerPoint: CGPoint(x: 0.875, y: 0.5)))
        XCTAssertEqual(mapped.hue, orange.hue, accuracy: 0.1)
        XCTAssertEqual([mapped.red, mapped.green, mapped.blue], [orange.red, orange.green, orange.blue])
    }

    func testRangesPersistRequireSchema23AndStampSeparately() throws {
        let legacy = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.targetedColors.isEmpty)
        XCTAssertFalse(legacy.hasTargetedColors)

        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
        var library = try repository.load()
        library.photos = [Photo(filename: "fixture.png", originalName: "fixture.png", projectID: nil,
                                width: 32, height: 20, camera: "", captureDate: "", sha256: "fixture")]
        library = try repository.save(library)
        var red = TargetedColorPreset.red.adjustment()
        red.hueShift = 12
        var blue = TargetedColorPreset.blue.adjustment()
        blue.luminance = -0.2
        library.photos[0].adjustments.targetedColors = [red, blue]
        var invalid = library
        invalid.version = 22
        XCTAssertThrowsError(try invalid.validateSchema())
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 23)
        XCTAssertEqual(try repository.load().photos[0].adjustments.targetedColors, [red, blue])
        XCTAssertTrue(saved.photos[0].adjustments.stamping(onto: Adjustments(), groups: [.basic]).targetedColors.isEmpty)
        XCTAssertEqual(saved.photos[0].adjustments.stamping(onto: Adjustments(), groups: [.targetedColor]).targetedColors,
                       [red, blue])
        XCTAssertEqual(AdjustmentPreset.vivid.applying(to: saved.photos[0].adjustments).targetedColors, [red, blue])
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueTargetedColor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func rgba(hue: Double, saturation: Double = 1, luminance: Double = 0.5) -> [UInt8] {
        let rgb = TargetedColorTools.rgb(hue: hue, saturation: saturation, luminance: luminance)
        return [rgb.red, rgb.green, rgb.blue].map { UInt8((min(1, max(0, $0)) * 255).rounded()) } + [255]
    }

    private func image(width: Int? = nil, colors: [[UInt8]]) throws -> CGImage {
        let width = width ?? colors.count
        let height = 40
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let color = colors[x * colors.count / width]
                data.replaceSubrange(((y * width + x) * 4)..<((y * width + x + 1) * 4), with: color)
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(data) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: width * 4, space: space,
                                     bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                         CGBitmapInfo.byteOrder32Big.rawValue), provider: provider,
                                     decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &result, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                  CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return result
    }

    private func pixel(_ image: CGImage, x: Int) throws -> [UInt8] {
        let values = try pixels(image)
        let offset = (20 * image.width + x) * 4
        return Array(values[offset..<(offset + 4)])
    }

    private func hsl(_ image: CGImage, x: Int) throws -> (hue: Double, saturation: Double, luminance: Double) {
        let value = try pixel(image, x: x)
        return TargetedColorTools.hsl(red: Double(value[0]) / 255, green: Double(value[1]) / 255,
                                      blue: Double(value[2]) / 255)
    }
    private func hue(_ image: CGImage, x: Int) throws -> Double { try hsl(image, x: x).hue }
    private func saturation(_ image: CGImage, x: Int) throws -> Double { try hsl(image, x: x).saturation }
    private func luminance(_ image: CGImage, x: Int) throws -> Double { try hsl(image, x: x).luminance }
}
