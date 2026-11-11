import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class BlackAndWhiteWorkspaceTests: XCTestCase {
    @MainActor
    func testUndoRedoPersistenceAndFullSizeViewerExportConsistency() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueBlackAndWhiteWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueBlackAndWhiteWorkspace-\(UUID().uuidString)"
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
        workspace.edit {
            $0.adjustments.blackAndWhiteEnabled = true
            $0.adjustments.blackAndWhiteRed = 0.35
            $0.adjustments.blackAndWhiteGreen = 0.55
            $0.adjustments.blackAndWhiteBlue = 0.1
            $0.adjustments.monochromeTintHue = 205
            $0.adjustments.monochromeTintStrength = 0.22
        }
        let corrected = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.library.version, 24)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = initial.id
        XCTAssertEqual(reopened.selected, corrected)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected, initial)
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected, corrected)

        let original = try repository.availableOriginalURL(corrected)
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
                values[offset] = UInt8(min(255, 30 + x))
                values[offset + 1] = UInt8(min(255, 50 + y))
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
