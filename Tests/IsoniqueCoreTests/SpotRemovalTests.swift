import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class SpotRemovalTests: XCTestCase {
    func testCloneRepairAndEdgeClippingProduceDistinctPixels() throws {
        try withFixture { source, _ in
            let sourcePoint = BrushPoint(x: 0.25, y: 0.5)
            let destination = BrushPoint(x: 0.75, y: 0.5)
            var clone = Adjustments()
            clone.spotRemovals = [SpotRemoval(mode: .clone, source: sourcePoint,
                                                destination: destination, radius: 0.14)]
            var repair = clone
            repair.spotRemovals[0].mode = .repair
            repair.spotRemovals.append(SpotRemoval(mode: .clone,
                                                    source: BrushPoint(x: 0.25, y: 0.5),
                                                    destination: BrushPoint(x: 0.01, y: 0.01), radius: 0.12))

            let neutral = try Renderer.render(source, adjustments: Adjustments())
            let cloned = try Renderer.render(source, adjustments: clone)
            let repaired = try Renderer.render(source, adjustments: repair)
            XCTAssertNotEqual(try pixel(cloned, x: 0.75, y: 0.5), try pixel(neutral, x: 0.75, y: 0.5))
            XCTAssertNotEqual(try pixel(repaired, x: 0.75, y: 0.5), try pixel(cloned, x: 0.75, y: 0.5))
            XCTAssertNotEqual(try pixel(repaired, x: 0, y: 0), try pixel(neutral, x: 0, y: 0))
            XCTAssertEqual(repaired.width, neutral.width)
            XCTAssertEqual(repaired.height, neutral.height)
        }
    }

    func testRecipePersistenceStampingAndViewerGeometryRoundTrip() throws {
        try withFixture { source, root in
            let repository = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
            var library = try repository.load()
            XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
            let spots = [
                SpotRemoval(mode: .repair, source: BrushPoint(x: 0.2, y: 0.3),
                            destination: BrushPoint(x: 0.4, y: 0.5), radius: 0.06),
                SpotRemoval(mode: .clone, source: BrushPoint(x: 0.7, y: 0.2),
                            destination: BrushPoint(x: 0.8, y: 0.7), radius: 0.1),
            ]
            library.photos[0].adjustments.spotRemovals = spots
            let saved = try repository.save(library)
            XCTAssertEqual(saved.version, 19)
            XCTAssertEqual(try repository.load().photos[0].adjustments.spotRemovals, spots)
            XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8)).spotRemovals, [])
            XCTAssertEqual(saved.photos[0].adjustments.stamping(onto: Adjustments(), groups: [.basic]).spotRemovals, [])
            XCTAssertEqual(saved.photos[0].adjustments.stamping(onto: Adjustments(), groups: [.retouch]).spotRemovals, spots)
            XCTAssertEqual(AdjustmentPreset.vivid.applying(to: saved.photos[0].adjustments).spotRemovals, spots)

            var geometryRecipe = saved.photos[0].adjustments
            geometryRecipe.quarterTurns = 1
            geometryRecipe.flipHorizontal = true
            geometryRecipe.flipVertical = true
            geometryRecipe.straighten = 8
            geometryRecipe.lensDistortion = 0.3
            geometryRecipe.crop = PhotoCrop(x: 0.08, y: 0.1, width: 0.84, height: 0.78)
            let (_, geometry) = try Renderer.renderWithGeometry(source, adjustments: geometryRecipe)
            for viewer in [CGPoint(x: 0.15, y: 0.2), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 0.82, y: 0.7)] {
                let sourcePoint = geometry.sourcePoint(x: viewer.x, y: viewer.y)
                let roundTrip = try XCTUnwrap(geometry.viewerPoint(sourcePoint))
                XCTAssertEqual(roundTrip.x, viewer.x, accuracy: 0.002)
                XCTAssertEqual(roundTrip.y, viewer.y, accuracy: 0.002)
            }
        }
    }

    func testFullSizePreviewAndPNGExportMatchAndPreserveOriginal() throws {
        try withFixture { source, root in
            let repository = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
            var library = try repository.load()
            XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
            let digest = try LibraryRepository.digest(source)
            library.photos[0].adjustments.spotRemovals = [
                SpotRemoval(mode: .repair, source: BrushPoint(x: 0.25, y: 0.5),
                            destination: BrushPoint(x: 0.75, y: 0.5), radius: 0.13),
                SpotRemoval(mode: .clone, source: BrushPoint(x: 0.25, y: 0.5),
                            destination: BrushPoint(x: 0.03, y: 0.03), radius: 0.08),
            ]
            let photo = try repository.save(library).photos[0]
            let preview = try Renderer.render(repository.availableOriginalURL(photo), adjustments: photo.adjustments)
            var options = ExportOptions()
            options.format = .png
            let output = root.appendingPathComponent("Retouched.png")
            try Renderer.export(photo, repository: repository, to: output, options: options)
            XCTAssertEqual(try pixels(preview), try pixels(decode(output)))
            XCTAssertEqual(try LibraryRepository.digest(source), digest)
            XCTAssertEqual(try LibraryRepository.digest(repository.availableOriginalURL(photo)), digest)

            var originalOptions = ExportOptions()
            originalOptions.format = .original
            let originalCopy = root.appendingPathComponent("Original.png")
            try Renderer.export(photo, repository: repository, to: originalCopy, options: originalOptions)
            XCTAssertEqual(try LibraryRepository.digest(originalCopy), digest)
        }
    }

    private func withFixture(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueSpot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Fixture.png")
        let context = try bitmap(width: 160, height: 100)
        context.setFillColor(red: 0.42, green: 0.42, blue: 0.42, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        context.setFillColor(red: 0.08, green: 0.72, blue: 0.24, alpha: 1)
        context.fill(CGRect(x: 37, y: 47, width: 7, height: 7))
        context.setFillColor(red: 0.92, green: 0.12, blue: 0.08, alpha: 1)
        context.fill(CGRect(x: 115, y: 45, width: 11, height: 11))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        try body(source, root)
    }

    private func bitmap(width: Int, height: Int) throws -> CGContext {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        return try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue))
    }

    private func decode(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try bitmap(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try Data(bytes: XCTUnwrap(context.data), count: image.width * image.height * 4)
    }

    private func pixel(_ image: CGImage, x: Double, y: Double) throws -> [UInt8] {
        let data = try pixels(image)
        let px = min(image.width - 1, max(0, Int(x * Double(image.width))))
        let py = min(image.height - 1, max(0, Int(y * Double(image.height))))
        let offset = (py * image.width + px) * 4
        return Array(data[offset..<(offset + 4)])
    }
}
