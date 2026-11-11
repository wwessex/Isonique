import CoreGraphics
import XCTest
@testable import IsoniqueCore

final class DefinitionTests: XCTestCase {
    func testNeutralAndFlatFieldsBypassWithoutColourShift() throws {
        let flat = try image(width: 72, height: 48) { _, _ in [82, 126, 171, 255] }
        XCTAssertEqual(try pixels(Renderer.applyDefinition(flat, strength: 0, radius: 8)), try pixels(flat))
        XCTAssertEqual(try pixels(Renderer.applyDefinition(flat, strength: 1, radius: 8)), try pixels(flat))

        let invalid = try Renderer.applyDefinition(flat, strength: .nan, radius: .infinity)
        XCTAssertEqual(try pixels(invalid), try pixels(flat))
    }

    func testFineTextureGainsLocalContrastAndRadiusChangesTheResult() throws {
        let texture = try image(width: 128, height: 64) { x, y in
            let base = (x / 8).isMultiple(of: 2) ? 112 : 144
            let detail = (x + y).isMultiple(of: 2) ? -3 : 3
            return [UInt8(base + detail), UInt8(base + 18 + detail), UInt8(base + 34 + detail), 255]
        }
        let small = try Renderer.applyDefinition(texture, strength: 1, radius: 0.25)
        let large = try Renderer.applyDefinition(texture, strength: 1, radius: 8)
        let beforeDifference = abs(Int(try pixel(texture, x: 34, y: 30)[0]) - Int(try pixel(texture, x: 35, y: 30)[0]))
        let afterDifference = abs(Int(try pixel(large, x: 34, y: 30)[0]) - Int(try pixel(large, x: 35, y: 30)[0]))
        XCTAssertGreaterThan(afterDifference, beforeDifference)
        XCTAssertNotEqual(try pixels(small), try pixels(large))

        let before = try pixel(texture, x: 35, y: 30)
        let after = try pixel(large, x: 35, y: 30)
        XCTAssertEqual(Int(after[0]) - Int(after[1]), Int(before[0]) - Int(before[1]), accuracy: 1)
        XCTAssertEqual(Int(after[1]) - Int(after[2]), Int(before[1]) - Int(before[2]), accuracy: 1)
    }

    func testHardEdgeHaloIsBoundedAndDistantPixelsStayNeutral() throws {
        let edge = try image(width: 128, height: 64) { x, _ in
            let value: UInt8 = x < 64 ? 48 : 208
            return [value, value, value, 255]
        }
        let output = try Renderer.applyDefinition(edge, strength: 1, radius: 8)
        XCTAssertEqual(try pixel(output, x: 20, y: 32), try pixel(edge, x: 20, y: 32))
        XCTAssertEqual(try pixel(output, x: 108, y: 32), try pixel(edge, x: 108, y: 32))
        XCTAssertNotEqual(try pixel(output, x: 63, y: 32), try pixel(edge, x: 63, y: 32))
        let source = try pixels(edge), result = try pixels(output)
        var maximumDifference = 0
        for offset in stride(from: 0, to: source.count, by: 4) {
            for channel in 0..<3 {
                maximumDifference = max(maximumDifference,
                    abs(Int(result[offset + channel]) - Int(source[offset + channel])))
            }
        }
        XCTAssertLessThanOrEqual(maximumDifference, 31)
    }

    func testRecipePersistsRequiresSchema26AndStampsWithDetail() throws {
        let legacy = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.definition, 0)
        XCTAssertEqual(legacy.definitionRadius, DefinitionRules.neutralRadius)
        XCTAssertFalse(legacy.hasDefinitionRecipe)

        var recipe = Adjustments()
        recipe.definition = 0.72
        recipe.definitionRadius = 4.5
        XCTAssertTrue(recipe.hasDefinitionRecipe)
        XCTAssertEqual(recipe.stamping(onto: Adjustments(), groups: [.detail]), recipe)
        XCTAssertEqual(recipe.stamping(onto: Adjustments(), groups: [.basic]).definition, 0)
        XCTAssertEqual(AdjustmentPreset.vivid.applying(to: recipe).definition, 0.72)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueDefinition-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        library.photos = [Photo(filename: "fixture.png", originalName: "fixture.png", projectID: nil,
                                width: 128, height: 64, camera: "", captureDate: "", sha256: "fixture")]
        library.photos[0].adjustments = recipe
        var invalid = library
        invalid.version = 25
        XCTAssertThrowsError(try invalid.validateSchema())
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 26)
        XCTAssertEqual(try repository.load().photos[0].adjustments.definition, 0.72)
        XCTAssertEqual(try repository.load().photos[0].adjustments.definitionRadius, 4.5)
    }

    private func image(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                data.replaceSubrange(((y * width + x) * 4)..<((y * width + x) * 4 + 4), with: value)
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
        let data = try pixels(image)
        let offset = (y * image.width + x) * 4
        return Array(data[offset..<(offset + 4)])
    }
}
