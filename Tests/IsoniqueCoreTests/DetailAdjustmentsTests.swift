import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class DetailAdjustmentsTests: XCTestCase {
    func testFlatFieldsRemainNeutralAndFiltersActOnLuminanceDetail() throws {
        let flat = try image(width: 32, height: 20) { _, _ in [96, 128, 160, 255] }
        XCTAssertEqual(try pixels(Renderer.applyLuminanceNoiseReduction(flat, amount: 1)), try pixels(flat))
        XCTAssertEqual(try pixels(Renderer.applySharpening(flat, sharpening: 1, edgeSharpening: 1)), try pixels(flat))

        let edge = try image(width: 32, height: 20) { x, _ in
            x < 16 ? [80, 100, 120, 255] : [168, 188, 208, 255]
        }
        let edgeSharpened = try Renderer.applySharpening(edge, sharpening: 0, edgeSharpening: 1)
        let globallySharpened = try Renderer.applySharpening(edge, sharpening: 1, edgeSharpening: 0)
        XCTAssertEqual(try pixel(edgeSharpened, x: 4, y: 10), try pixel(edge, x: 4, y: 10))
        XCTAssertLessThan(try pixel(edgeSharpened, x: 15, y: 10)[0], try pixel(edge, x: 15, y: 10)[0])
        XCTAssertGreaterThan(try pixel(edgeSharpened, x: 16, y: 10)[0], try pixel(edge, x: 16, y: 10)[0])
        XCTAssertLessThan(try pixel(globallySharpened, x: 15, y: 10)[0], try pixel(edge, x: 15, y: 10)[0])
        XCTAssertGreaterThan(try pixel(globallySharpened, x: 16, y: 10)[0], try pixel(edge, x: 16, y: 10)[0])
        XCTAssertEqual(try pixels(Renderer.applyLuminanceNoiseReduction(edge, amount: 1)), try pixels(edge),
                       "Noise reduction should not blur a high-contrast edge")

        let noise = try image(width: 64, height: 24) { x, y in
            let offset = (x + y).isMultiple(of: 2) ? 18 : -18
            return [UInt8(120 + offset), UInt8(100 + offset), UInt8(80 + offset), 255]
        }
        let reduced = try Renderer.applyLuminanceNoiseReduction(noise, amount: 1)
        XCTAssertLessThan(try luminanceVariance(reduced), try luminanceVariance(noise) * 0.15)
        let before = try pixel(noise, x: 31, y: 12)
        let after = try pixel(reduced, x: 31, y: 12)
        XCTAssertEqual(Int(after[0]) - Int(after[1]), Int(before[0]) - Int(before[1]), accuracy: 1)
        XCTAssertEqual(Int(after[1]) - Int(after[2]), Int(before[1]) - Int(before[2]), accuracy: 1)
    }

    func testOlderRecipesStayNeutralAndDetailRecipesPersistAndStampSeparately() throws {
        let legacy = try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
        XCTAssertEqual(legacy.sharpening, 0)
        XCTAssertEqual(legacy.edgeSharpening, 0)
        XCTAssertEqual(legacy.luminanceNoiseReduction, 0)
        XCTAssertFalse(legacy.hasDetailAdjustments)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueDetailSchema-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        let photo = Photo(filename: "fixture.png", originalName: "fixture.png", projectID: nil,
                          width: 32, height: 20, camera: "", captureDate: "", sha256: "fixture")
        library.photos = [photo]
        library = try repository.save(library)
        XCTAssertEqual(library.version, 1)
        library.photos[0].adjustments.sharpening = 0.6
        library.photos[0].adjustments.edgeSharpening = 0.4
        library.photos[0].adjustments.luminanceNoiseReduction = 0.7
        var invalidLegacyCatalogue = library
        invalidLegacyCatalogue.version = 19
        XCTAssertThrowsError(try invalidLegacyCatalogue.validateSchema())
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 20)
        let detail = saved.photos[0].adjustments
        XCTAssertEqual(try repository.load().photos[0].adjustments, detail)
        XCTAssertEqual(AdjustmentPreset.vivid.applying(to: detail).sharpening, 0.6)
        XCTAssertEqual(detail.stamping(onto: Adjustments(), groups: [.basic]).sharpening, 0)
        XCTAssertEqual(detail.stamping(onto: Adjustments(), groups: [.detail]), detail)
    }

    func testFullSizePNGExportMatchesSharedRendererAndPreservesOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueDetailExport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.png")
        try writeFixture(source)
        let digest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments.sharpening = 0.65
        library.photos[0].adjustments.edgeSharpening = 0.45
        library.photos[0].adjustments.luminanceNoiseReduction = 0.55
        let photo = try repository.save(library).photos[0]
        let preview = try Renderer.render(repository.availableOriginalURL(photo), adjustments: photo.adjustments)
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Detailed.png")
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
        let fixture = try image(width: 160, height: 96) { x, y in
            let base = x < 80 ? 88 : 166
            let noise = (x + y).isMultiple(of: 2) ? 12 : -12
            return [UInt8(base + noise), UInt8(base + 18 + noise), UInt8(base + 34 + noise), 255]
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

    private func luminanceVariance(_ image: CGImage) throws -> Double {
        let values = try pixels(image)
        let luminances = stride(from: 0, to: values.count, by: 4).map { offset in
            0.2126 * Double(values[offset]) + 0.7152 * Double(values[offset + 1]) + 0.0722 * Double(values[offset + 2])
        }
        let mean = luminances.reduce(0, +) / Double(luminances.count)
        return luminances.reduce(0) { $0 + pow($1 - mean, 2) } / Double(luminances.count)
    }
}
