import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class LensEffectsTests: XCTestCase {
    func testAberrationMovesOnlyRequestedChannelsAndClampsEdges() throws {
        let source = try image(width: 256, height: 48) { x, _ in
            x < 220 ? [20, 96, 240, 255] : [240, 96, 20, 255]
        }
        XCTAssertEqual(try pixels(Renderer.applyChromaticAberration(source, redCyan: 0, blueYellow: 0)),
                       try pixels(source))
        let corrected = try Renderer.applyChromaticAberration(source, redCyan: 1, blueYellow: -1)
        XCTAssertEqual(corrected.width, source.width)
        XCTAssertEqual(corrected.height, source.height)
        XCTAssertGreaterThan(try pixel(corrected, x: 219, y: 24)[0], try pixel(source, x: 219, y: 24)[0])
        XCTAssertGreaterThan(try pixel(corrected, x: 220, y: 24)[2], try pixel(source, x: 220, y: 24)[2])
        XCTAssertEqual(try pixel(corrected, x: 219, y: 24)[1], try pixel(source, x: 219, y: 24)[1])
        XCTAssertEqual(try pixel(corrected, x: 255, y: 24)[0], try pixel(source, x: 255, y: 24)[0])

        let reversed = try Renderer.applyChromaticAberration(source, redCyan: -1, blueYellow: 1)
        XCTAssertLessThan(try pixel(reversed, x: 220, y: 24)[0], try pixel(source, x: 220, y: 24)[0])
        XCTAssertLessThan(try pixel(reversed, x: 219, y: 24)[2], try pixel(source, x: 219, y: 24)[2])
    }

    func testVignetteAndDevignettePreserveCentreAndChangeCorners() throws {
        let source = try image(width: 96, height: 64) { _, _ in [100, 120, 140, 255] }
        let vignette = try Renderer.applyVignette(source, amount: 1)
        let devignette = try Renderer.applyDevignette(source, amount: 1)
        XCTAssertEqual(try pixel(vignette, x: 48, y: 32), try pixel(source, x: 48, y: 32))
        XCTAssertEqual(try pixel(devignette, x: 48, y: 32), try pixel(source, x: 48, y: 32))
        XCTAssertLessThan(try pixel(vignette, x: 0, y: 0)[0], try pixel(source, x: 0, y: 0)[0])
        XCTAssertGreaterThan(try pixel(devignette, x: 0, y: 0)[0], try pixel(source, x: 0, y: 0)[0])
        XCTAssertEqual(try pixels(Renderer.applyVignette(source, amount: 0)), try pixels(source))
        XCTAssertEqual(try pixels(Renderer.applyDevignette(source, amount: 0)), try pixels(source))
    }

    func testOlderRecipesStayNeutralAndLensEffectsPersistAndStampSeparately() throws {
        let legacy = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.chromaticAberrationRedCyan, 0)
        XCTAssertEqual(legacy.chromaticAberrationBlueYellow, 0)
        XCTAssertEqual(legacy.vignette, 0)
        XCTAssertEqual(legacy.devignette, 0)
        XCTAssertFalse(legacy.hasLensEffects)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueLensSchema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        library.photos = [Photo(filename: "fixture.png", originalName: "fixture.png", projectID: nil,
                                width: 32, height: 20, camera: "", captureDate: "", sha256: "fixture")]
        library = try repository.save(library)
        XCTAssertEqual(library.version, 1)
        library.photos[0].adjustments.chromaticAberrationRedCyan = 0.4
        library.photos[0].adjustments.chromaticAberrationBlueYellow = -0.3
        library.photos[0].adjustments.vignette = 0.5
        library.photos[0].adjustments.devignette = 0.2
        var invalidOlderCatalogue = library
        invalidOlderCatalogue.version = 20
        XCTAssertThrowsError(try invalidOlderCatalogue.validateSchema())
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 21)
        let effects = saved.photos[0].adjustments
        XCTAssertEqual(try repository.load().photos[0].adjustments, effects)
        XCTAssertEqual(AdjustmentPreset.vivid.applying(to: effects).vignette, 0.5)
        XCTAssertFalse(effects.stamping(onto: Adjustments(), groups: [.basic]).hasLensEffects)
        XCTAssertEqual(effects.stamping(onto: Adjustments(), groups: [.lensEffects]), effects)
    }

    func testGeometryFullSizeExportAndOriginalPreservation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueLensExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.png")
        try writeFixture(source)
        let digest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        var settings = library.photos[0].adjustments
        settings.chromaticAberrationRedCyan = 0.8
        settings.chromaticAberrationBlueYellow = -0.6
        settings.vignette = 0.75
        settings.devignette = 0.35
        settings.quarterTurns = 1
        settings.flipHorizontal = true
        settings.straighten = 4
        settings.crop = PhotoCrop(x: 0.08, y: 0.1, width: 0.82, height: 0.76)
        settings.lensDistortion = 0.2
        library.photos[0].adjustments = settings
        let photo = try repository.save(library).photos[0]
        let preview = try Renderer.render(repository.availableOriginalURL(photo), adjustments: settings)
        var withoutVignette = settings
        withoutVignette.vignette = 0
        let neutralFrame = try Renderer.render(repository.availableOriginalURL(photo), adjustments: withoutVignette)
        XCTAssertEqual(preview.width, neutralFrame.width)
        XCTAssertEqual(preview.height, neutralFrame.height)
        XCTAssertLessThan(try pixel(preview, x: 0, y: 0)[0], try pixel(neutralFrame, x: 0, y: 0)[0])

        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Corrected.png")
        try Renderer.export(photo, repository: repository, to: output, options: options)
        XCTAssertEqual(try pixels(preview), try pixels(decode(output)))
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
        XCTAssertEqual(try LibraryRepository.digest(repository.availableOriginalURL(photo)), digest)

        var originalOptions = ExportOptions()
        originalOptions.format = .original
        let originalCopy = folder.appendingPathComponent("Original.png")
        try Renderer.export(photo, repository: repository, to: originalCopy, options: originalOptions)
        XCTAssertEqual(try LibraryRepository.digest(originalCopy), digest)
    }

    private func writeFixture(_ url: URL) throws {
        let fixture = try image(width: 180, height: 112) { x, y in
            let edge = x < 90 ? 70 : 178
            return [UInt8(edge), UInt8(min(255, edge + y / 8)), UInt8(min(255, edge + 28)), 255]
        }
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, fixture, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }

    private func image(width: Int, height: Int, pixel: (Int, Int) -> [UInt8]) throws -> CGImage {
        var data = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value = pixel(x, y)
                let offset = (y * width + x) * 4
                data.replaceSubrange(offset..<(offset + 4), with: value)
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

    private func decode(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
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
