import CoreGraphics
import XCTest
@testable import IsoniqueCore

final class RedEyeTests: XCTestCase {
    func testCorrectionClipsAtEdgesDarkensRedPixelsAndPreservesNonRedPixels() throws {
        let source = try fixture()
        let central = RedEyeCorrection(center: BrushPoint(x: 0.5, y: 0.5), radius: 0.16, darkness: 0)
        let edge = RedEyeCorrection(center: BrushPoint(x: 0.01, y: 0.01), radius: 0.18, darkness: 1)
        let output = try Renderer.applyRedEyeCorrections(source, corrections: [central, edge])

        let originalCentre = try pixel(source, x: 32, y: 24)
        let correctedCentre = try pixel(output, x: 32, y: 24)
        XCTAssertLessThan(correctedCentre[0], originalCentre[0])
        XCTAssertEqual(correctedCentre[3], originalCentre[3])
        XCTAssertLessThan(try pixel(output, x: 0, y: 0)[0], try pixel(source, x: 0, y: 0)[0])
        XCTAssertEqual(try pixel(output, x: 28, y: 24), try pixel(source, x: 28, y: 24),
                       "A green pixel inside the pupil region must remain byte-identical")
        XCTAssertEqual(try pixel(output, x: 27, y: 22), try pixel(source, x: 27, y: 22),
                       "A neutral pixel inside the pupil region must remain byte-identical")
        XCTAssertEqual(output.width, source.width)
        XCTAssertEqual(output.height, source.height)

        let dark = try Renderer.applyRedEyeCorrections(source, corrections: [
            RedEyeCorrection(center: central.center, radius: central.radius, darkness: 1),
        ])
        XCTAssertLessThan(try pixel(dark, x: 32, y: 24).prefix(3).reduce(0, { $0 + Int($1) }),
                          correctedCentre.prefix(3).reduce(0, { $0 + Int($1) }))
    }

    func testInvalidOrEmptyCorrectionsBypassExactly() throws {
        let source = try fixture()
        XCTAssertEqual(try pixels(Renderer.applyRedEyeCorrections(source, corrections: [])), try pixels(source))
        let invalid = RedEyeCorrection(center: BrushPoint(x: 0.5, y: 0.5), radius: 0.9, darkness: 0.5)
        XCTAssertEqual(try pixels(Renderer.applyRedEyeCorrections(source, corrections: [invalid])), try pixels(source))
    }

    func testRecipePersistsRequiresSchema25AndStampsSeparately() throws {
        let legacy = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertTrue(legacy.redEyeCorrections.isEmpty)
        let corrections = [
            RedEyeCorrection(center: BrushPoint(x: 0.32, y: 0.44), radius: 0.07, darkness: 0.35),
            RedEyeCorrection(center: BrushPoint(x: 0.68, y: 0.45), radius: 0.08, darkness: 0.7),
        ]
        var recipe = Adjustments()
        recipe.redEyeCorrections = corrections
        XCTAssertTrue(recipe.hasRedEyeCorrections)
        XCTAssertTrue(recipe.stamping(onto: Adjustments(), groups: [.basic]).redEyeCorrections.isEmpty)
        XCTAssertEqual(recipe.stamping(onto: Adjustments(), groups: [.redEye]).redEyeCorrections, corrections)
        XCTAssertEqual(AdjustmentPreset.vivid.applying(to: recipe).redEyeCorrections, corrections)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueRedEye-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        library.photos = [Photo(filename: "fixture.png", originalName: "fixture.png", projectID: nil,
                                width: 64, height: 48, camera: "", captureDate: "", sha256: "fixture")]
        library.photos[0].adjustments = recipe
        var invalid = library
        invalid.version = 24
        XCTAssertThrowsError(try invalid.validateSchema())
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 25)
        XCTAssertEqual(try repository.load().photos[0].adjustments.redEyeCorrections, corrections)
    }

    private func fixture() throws -> CGImage {
        let width = 64, height = 48
        var values = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let colour: [UInt8]
                if x < 5, y < 5 { colour = [240, 20, 20, 255] }
                else if (30...34).contains(x), (22...26).contains(y) { colour = [230, 30, 25, 255] }
                else if x == 28, y == 24 { colour = [20, 210, 40, 255] }
                else { colour = [96, 96, 96, 255] }
                values[offset] = colour[0]
                values[offset + 1] = colour[1]
                values[offset + 2] = colour[2]
                values[offset + 3] = colour[3]
            }
        }
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

    private func pixel(_ image: CGImage, x: Int, y: Int) throws -> [UInt8] {
        let data = try pixels(image)
        let offset = (y * image.width + x) * 4
        return Array(data[offset..<(offset + 4)])
    }
}
