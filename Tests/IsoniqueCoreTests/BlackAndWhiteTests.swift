import CoreGraphics
import XCTest
@testable import IsoniqueCore

final class BlackAndWhiteTests: XCTestCase {
    func testDisabledBypassesAndNeutralMixerUsesRec709Luminance() throws {
        let source = try image(colors: [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [0, 0, 0, 0]])
        XCTAssertEqual(try pixels(Renderer.applyBlackAndWhite(source, enabled: false,
            red: 2, green: 2, blue: 2, tintHue: 120, tintStrength: 1)), try pixels(source))
        let output = try Renderer.applyBlackAndWhite(source, enabled: true,
            red: BlackAndWhiteRules.neutralRed, green: BlackAndWhiteRules.neutralGreen,
            blue: BlackAndWhiteRules.neutralBlue, tintHue: 30, tintStrength: 0)
        XCTAssertEqual(Array(try pixel(output, x: 0)[0...2]), [54, 54, 54])
        XCTAssertEqual(Array(try pixel(output, x: 1)[0...2]), [182, 182, 182])
        XCTAssertEqual(Array(try pixel(output, x: 2)[0...2]), [18, 18, 18])
        XCTAssertEqual(try pixel(output, x: 3), [0, 0, 0, 0])
    }

    func testChannelIsolationAndContributionBounds() throws {
        let source = try image(colors: [[60, 120, 200, 255]])
        let red = try Renderer.applyBlackAndWhite(source, enabled: true, red: 1, green: 0, blue: 0,
                                                   tintHue: 0, tintStrength: 0)
        let green = try Renderer.applyBlackAndWhite(source, enabled: true, red: 0, green: 1, blue: 0,
                                                     tintHue: 0, tintStrength: 0)
        let blue = try Renderer.applyBlackAndWhite(source, enabled: true, red: 0, green: 0, blue: 1,
                                                    tintHue: 0, tintStrength: 0)
        XCTAssertEqual(Array(try pixel(red, x: 0)[0...2]), [60, 60, 60])
        XCTAssertEqual(Array(try pixel(green, x: 0)[0...2]), [120, 120, 120])
        XCTAssertEqual(Array(try pixel(blue, x: 0)[0...2]), [200, 200, 200])

        let white = try Renderer.applyBlackAndWhite(source, enabled: true, red: 99, green: 99, blue: 99,
                                                     tintHue: 0, tintStrength: 0)
        let black = try Renderer.applyBlackAndWhite(source, enabled: true, red: -1, green: -.infinity, blue: .nan,
                                                     tintHue: 0, tintStrength: 0)
        XCTAssertEqual(Array(try pixel(white, x: 0)[0...2]), [255, 255, 255])
        XCTAssertEqual(Array(try pixel(black, x: 0)[0...2]), [0, 0, 0])
    }

    func testOptionalTintPreservesLightnessAndWrapsHue() throws {
        let source = try image(colors: [[128, 128, 128, 255]])
        let neutral = try Renderer.applyBlackAndWhite(source, enabled: true,
            red: BlackAndWhiteRules.neutralRed, green: BlackAndWhiteRules.neutralGreen,
            blue: BlackAndWhiteRules.neutralBlue, tintHue: 390, tintStrength: 0)
        XCTAssertEqual(Array(try pixel(neutral, x: 0)[0...2]), [128, 128, 128])
        let tinted = try Renderer.applyBlackAndWhite(source, enabled: true,
            red: BlackAndWhiteRules.neutralRed, green: BlackAndWhiteRules.neutralGreen,
            blue: BlackAndWhiteRules.neutralBlue, tintHue: 390, tintStrength: 0.5)
        let value = try pixel(tinted, x: 0)
        let hsl = TargetedColorTools.hsl(red: Double(value[0]) / 255, green: Double(value[1]) / 255,
                                         blue: Double(value[2]) / 255)
        XCTAssertEqual(hsl.hue, 30, accuracy: 1)
        XCTAssertEqual(hsl.saturation, 0.5, accuracy: 0.02)
        XCTAssertEqual(hsl.luminance, 128.0 / 255, accuracy: 0.01)
    }

    func testRecipePersistsRequiresSchema24AndStampsSeparately() throws {
        let legacy = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertFalse(legacy.blackAndWhiteEnabled)
        XCTAssertEqual(legacy.blackAndWhiteRed, BlackAndWhiteRules.neutralRed)
        XCTAssertEqual(legacy.blackAndWhiteGreen, BlackAndWhiteRules.neutralGreen)
        XCTAssertEqual(legacy.blackAndWhiteBlue, BlackAndWhiteRules.neutralBlue)
        XCTAssertEqual(legacy.monochromeTintStrength, 0)
        XCTAssertFalse(legacy.hasBlackAndWhiteRecipe)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueBlackAndWhite-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        library.photos = [Photo(filename: "fixture.png", originalName: "fixture.png", projectID: nil,
                                width: 32, height: 20, camera: "", captureDate: "", sha256: "fixture")]
        library = try repository.save(library)
        var recipe = library.photos[0].adjustments
        recipe.blackAndWhiteEnabled = true
        recipe.blackAndWhiteRed = 0.4
        recipe.blackAndWhiteGreen = 0.5
        recipe.blackAndWhiteBlue = 0.1
        recipe.monochromeTintHue = 215
        recipe.monochromeTintStrength = 0.3
        library.photos[0].adjustments = recipe
        var invalid = library
        invalid.version = 23
        XCTAssertThrowsError(try invalid.validateSchema())
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 24)
        XCTAssertEqual(try repository.load().photos[0].adjustments, recipe)
        XCTAssertFalse(recipe.stamping(onto: Adjustments(), groups: [.basic]).hasBlackAndWhiteRecipe)
        XCTAssertEqual(recipe.stamping(onto: Adjustments(), groups: [.blackAndWhite]), recipe)
        XCTAssertTrue(AdjustmentPreset.monochrome.applying(to: Adjustments()).blackAndWhiteEnabled)
        XCTAssertFalse(AdjustmentPreset.vivid.applying(to: recipe).blackAndWhiteEnabled)
    }

    private func image(colors: [[UInt8]]) throws -> CGImage {
        let width = colors.count, height = 24
        let values = Array(repeating: colors.flatMap { $0 }, count: height).flatMap { $0 }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(values) as CFData))
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

    private func pixel(_ image: CGImage, x: Int) throws -> [UInt8] {
        let values = try pixels(image)
        let offset = (12 * image.width + x) * 4
        return Array(values[offset..<(offset + 4)])
    }
}
