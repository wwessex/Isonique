import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class WhiteBalanceTests: XCTestCase {
    func testNeutralOlderRecipeAndKelvinTintDirections() throws {
        let legacy = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.temperatureKelvin, WhiteBalanceRules.neutralKelvin)
        XCTAssertFalse(legacy.hasKelvinWhiteBalance)

        let source = try image(width: 8, height: 8) { _, _ in [120, 120, 120, 255] }
        XCTAssertEqual(try pixels(Renderer.applyTone(source, adjustments: legacy)), try pixels(source))

        var warm = legacy
        warm.temperatureKelvin = WhiteBalanceRules.maximumKelvin
        let warmed = try pixel(Renderer.applyTone(source, adjustments: warm), x: 4, y: 4)
        XCTAssertGreaterThan(warmed[0], 120)
        XCTAssertLessThan(warmed[2], 120)

        var magenta = legacy
        magenta.tint = 1
        let tinted = try pixel(Renderer.applyTone(source, adjustments: magenta), x: 4, y: 4)
        XCTAssertGreaterThan(tinted[0], tinted[1])
        XCTAssertGreaterThan(tinted[2], tinted[1])

        var oldWarmth = legacy
        oldWarmth.warmth = 0.4
        XCTAssertGreaterThan(try pixel(Renderer.applyTone(source, adjustments: oldWarmth), x: 4, y: 4)[0], 120)
        XCTAssertGreaterThan(oldWarmth.displayedTemperatureKelvin, WhiteBalanceRules.neutralKelvin)
    }

    func testEyedropperNeutralisesCastUsesGeometryAndRejectsInvalidPixels() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Samples.png")
        let fixture = try image(width: 400, height: 80) { x, _ in
            switch x / 100 {
            case 0: return [140, 130, 120, 255]
            case 1: return [255, 128, 128, 255]
            case 2: return [0, 0, 0, 0]
            default: return [120, 120, 120, 255]
            }
        }
        try write(fixture, to: source)

        let cast = try XCTUnwrap(Renderer.sampleWhiteBalance(source, adjustments: Adjustments(),
                                                              viewerPoint: CGPoint(x: 0.125, y: 0.5)))
        XCTAssertEqual([cast.red, cast.green, cast.blue], [140, 130, 120])
        XCTAssertLessThan(cast.kelvin, WhiteBalanceRules.neutralKelvin)
        XCTAssertNil(try Renderer.sampleWhiteBalance(source, adjustments: Adjustments(),
                                                      viewerPoint: CGPoint(x: 0.375, y: 0.5)))
        XCTAssertNil(try Renderer.sampleWhiteBalance(source, adjustments: Adjustments(),
                                                      viewerPoint: CGPoint(x: 0.625, y: 0.5)))
        let neutral = try XCTUnwrap(Renderer.sampleWhiteBalance(source, adjustments: Adjustments(),
                                                                 viewerPoint: CGPoint(x: 0.875, y: 0.5)))
        XCTAssertEqual(neutral.kelvin, WhiteBalanceRules.neutralKelvin, accuracy: 0.001)
        XCTAssertEqual(neutral.tint, 0, accuracy: 0.001)

        var flipped = Adjustments()
        flipped.flipHorizontal = true
        let mapped = try XCTUnwrap(Renderer.sampleWhiteBalance(source, adjustments: flipped,
                                                                viewerPoint: CGPoint(x: 0.875, y: 0.5)))
        XCTAssertEqual([mapped.red, mapped.green, mapped.blue], [140, 130, 120])

        var corrected = Adjustments()
        corrected.temperatureKelvin = cast.kelvin
        corrected.tint = cast.tint
        let rendered = try Renderer.render(source, adjustments: corrected)
        let balanced = try pixel(rendered, x: 50, y: 40)
        XCTAssertLessThanOrEqual((balanced[0...2].max() ?? 0) - (balanced[0...2].min() ?? 0), 2)
    }

    func testKelvinPersistsRequiresSchema22AndStampsWithWhiteBalance() throws {
        let root = try makeFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
        var library = try repository.load()
        library.photos = [Photo(filename: "fixture.png", originalName: "fixture.png", projectID: nil,
                                width: 32, height: 20, camera: "", captureDate: "", sha256: "fixture")]
        library = try repository.save(library)
        library.photos[0].adjustments.temperatureKelvin = 8_200
        library.photos[0].adjustments.tint = -0.2
        var invalid = library
        invalid.version = 21
        XCTAssertThrowsError(try invalid.validateSchema())
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 22)
        XCTAssertEqual(try repository.load().photos[0].adjustments.temperatureKelvin, 8_200)
        let stamped = saved.photos[0].adjustments.stamping(onto: Adjustments(), groups: [.whiteBalance])
        XCTAssertEqual(stamped.temperatureKelvin, 8_200)
        XCTAssertEqual(stamped.tint, -0.2)
        XCTAssertEqual(AdjustmentPreset.vivid.applying(to: stamped).temperatureKelvin,
                       WhiteBalanceRules.neutralKelvin)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueWhiteBalance-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func write(_ image: CGImage, to url: URL) throws {
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func image(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                data.replaceSubrange(offset..<(offset + 4), with: pixel(x, y))
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

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let values = try pixels(image)
        let offset = (y * image.width + x) * 4
        return Array(values[offset..<(offset + 4)])
    }
}
