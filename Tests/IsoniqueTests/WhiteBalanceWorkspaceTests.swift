import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class WhiteBalanceWorkspaceTests: XCTestCase {
    @MainActor
    func testLoupeWhiteBalanceUndoRedoPersistenceAndFullSizeExportConsistency() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueWhiteBalanceWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueWhiteBalanceWorkspace-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            preferences.removePersistentDomain(forName: suite)
        }
        preferences.set(true, forKey: "history.persist")
        let source = folder.appendingPathComponent("Source.png")
        try writeFixture(source)
        let sourceDigest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        library = try repository.save(library)
        let initial = try XCTUnwrap(library.photos.first)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.selection = initial.id
        workspace.startWhiteBalanceSampling(photoID: initial.id)
        let request = try XCTUnwrap(workspace.activeWhiteBalanceSampling)
        let original = try repository.availableOriginalURL(initial)
        let work = WhiteBalanceSampleWork(request: request, point: CGPoint(x: 0.5, y: 0.5))
        let sample = try await work.load(from: original)
        workspace.finishWhiteBalanceSampling(request, sample: sample)
        let corrected = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertNil(workspace.activeWhiteBalanceSampling)
        XCTAssertEqual(workspace.library.version, 22)
        XCTAssertNotEqual(corrected.adjustments.temperatureKelvin, WhiteBalanceRules.neutralKelvin)
        XCTAssertEqual(corrected.adjustments.warmth, 0)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = initial.id
        XCTAssertEqual(reopened.selected, corrected)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected, initial)
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected, corrected)

        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: corrected.adjustments,
                                                                 maximum: nil, revision: 0)
        let centre = try pixel(viewer.image, x: viewer.image.width / 2, y: viewer.image.height / 2)
        XCTAssertLessThanOrEqual((centre[0...2].max() ?? 0) - (centre[0...2].min() ?? 0), 3)
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Export.png")
        try Renderer.export(corrected, repository: repository, to: output, options: options)
        let exported = try decode(output)
        XCTAssertEqual(try pixels(viewer.image), try pixels(exported))
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
    }

    private func writeFixture(_ url: URL) throws {
        let width = 192, height = 112
        var values = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: values.count, by: 4) {
            values[offset] = 140
            values[offset + 1] = 130
            values[offset + 2] = 120
            values[offset + 3] = 255
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(values) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue), provider: provider,
                                          decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
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
