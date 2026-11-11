import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class TargetedColorWorkspaceTests: XCTestCase {
    @MainActor
    func testSampledRangeUndoRedoPersistenceAndFullSizeExportConsistency() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueTargetedColorWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueTargetedColorWorkspace-\(UUID().uuidString)"
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
        workspace.startTargetedColorSampling(photoID: initial.id)
        let request = try XCTUnwrap(workspace.activeTargetedColorSampling)
        let original = try repository.availableOriginalURL(initial)
        let work = TargetedColorSampleWork(request: request, point: CGPoint(x: 0.5, y: 0.5))
        let sample = try await work.load(from: original)
        workspace.finishTargetedColorSampling(request, sample: sample)
        let sampled = try XCTUnwrap(workspace.selected)
        let targetID = try XCTUnwrap(sampled.adjustments.targetedColors.first?.id)
        XCTAssertEqual(workspace.targetedColorSelection, targetID)
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.library.version, 23)
        XCTAssertNil(workspace.activeTargetedColorSampling)

        workspace.edit { photo in
            photo.adjustments.targetedColors[0].hueShift = 24
            photo.adjustments.targetedColors[0].saturation = 0.35
            photo.adjustments.targetedColors[0].luminance = -0.12
        }
        let corrected = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(workspace.history.undo.count, 2)
        XCTAssertNotEqual(corrected.adjustments.targetedColors, sampled.adjustments.targetedColors)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = initial.id
        XCTAssertEqual(reopened.selected, corrected)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected, sampled)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected, initial)
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected, sampled)
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected, corrected)

        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: corrected.adjustments,
                                                                 maximum: nil, revision: 0)
        XCTAssertNotEqual(try pixels(viewer.image), try pixels(Renderer.render(original, adjustments: initial.adjustments)))
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Export.png")
        try Renderer.export(corrected, repository: repository, to: output, options: options)
        XCTAssertEqual(try pixels(viewer.image), try pixels(decode(output)))
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
    }

    private func writeFixture(_ url: URL) throws {
        let width = 192, height = 112
        var values = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                values[offset] = UInt8(min(245, 190 + x / 5))
                values[offset + 1] = UInt8(min(180, 90 + y / 3))
                values[offset + 2] = 35
                values[offset + 3] = 255
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(values) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                          bytesPerRow: width * 4, space: space,
                                          bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                              CGBitmapInfo.byteOrder32Big.rawValue), provider: provider,
                                          decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
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
}
