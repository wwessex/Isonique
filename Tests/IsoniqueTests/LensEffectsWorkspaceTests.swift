import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class LensEffectsWorkspaceTests: XCTestCase {
    @MainActor
    func testLensEffectsUndoRedoPersistenceAndFullSizeViewerExportConsistency() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueLensWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueLensWorkspace-\(UUID().uuidString)"
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
        try repository.save(library)
        let photoID = try XCTUnwrap(library.photos.first?.id)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.selection = photoID
        workspace.edit { $0.adjustments.chromaticAberrationRedCyan = 0.7 }
        workspace.edit { $0.adjustments.chromaticAberrationBlueYellow = -0.55 }
        workspace.edit { $0.adjustments.vignette = 0.6 }
        workspace.edit { $0.adjustments.devignette = 0.3 }
        XCTAssertEqual(workspace.history.undo.count, 4)
        XCTAssertEqual(workspace.library.version, 21)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.selected?.adjustments.chromaticAberrationRedCyan, 0.7)
        XCTAssertEqual(reopened.selected?.adjustments.chromaticAberrationBlueYellow, -0.55)
        XCTAssertEqual(reopened.selected?.adjustments.vignette, 0.6)
        XCTAssertEqual(reopened.selected?.adjustments.devignette, 0.3)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.devignette, 0)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.vignette, 0)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.chromaticAberrationBlueYellow, 0)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.chromaticAberrationRedCyan, 0)
        for _ in 0..<4 { reopened.redoEdit() }
        let corrected = try XCTUnwrap(reopened.selected)
        XCTAssertEqual(corrected.adjustments.chromaticAberrationRedCyan, 0.7)
        XCTAssertEqual(corrected.adjustments.chromaticAberrationBlueYellow, -0.55)
        XCTAssertEqual(corrected.adjustments.vignette, 0.6)
        XCTAssertEqual(corrected.adjustments.devignette, 0.3)

        let original = try repository.availableOriginalURL(corrected)
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: corrected.adjustments,
                                                                 maximum: nil, revision: 0)
        XCTAssertEqual(viewer.image.width, 192)
        XCTAssertEqual(viewer.image.height, 112)
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Export.png")
        try Renderer.export(corrected, repository: repository, to: output, options: options)
        let exported = try decode(output)
        XCTAssertEqual(exported.width, 192)
        XCTAssertEqual(exported.height, 112)
        XCTAssertEqual(try pixels(viewer.image), try pixels(exported))
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
    }

    private func writeFixture(_ url: URL) throws {
        let width = 192, height = 112
        var values = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                values[offset] = UInt8(min(255, 40 + x))
                values[offset + 1] = UInt8(min(255, 76 + y))
                values[offset + 2] = UInt8(max(0, 230 - x))
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
}
