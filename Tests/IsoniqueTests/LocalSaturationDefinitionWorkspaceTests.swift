import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class LocalSaturationDefinitionWorkspaceTests: XCTestCase {
    @MainActor
    func testUndoRedoPersistenceFullSizeExportAndOriginalPreservation() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueLocalEffectsWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueLocalEffectsWorkspace-\(UUID().uuidString)"
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
        let photoID = try XCTUnwrap(library.photos.first?.id)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.selection = photoID
        workspace.chooseBrush(.saturation)
        let saturation = LocalBrushStroke(adjustment: .saturation, radius: 0.22, softness: 0.4,
            strength: 0.9, edgeAware: true, points: [BrushPoint(x: 0.48, y: 0.5)])
        workspace.applyBrushStroke(saturation, to: photoID)
        workspace.chooseBrush(.definition)
        let definition = LocalBrushStroke(adjustment: .definition, radius: 0.2, softness: 0.3,
            strength: 0.8, edgeAware: true, points: [BrushPoint(x: 0.52, y: 0.5)])
        workspace.applyBrushStroke(definition, to: photoID)
        workspace.setBrushMaskOpacity(0.55, for: .saturation)
        workspace.invertBrushMask(.definition)
        XCTAssertEqual(workspace.history.undo.count, 4)
        XCTAssertEqual(workspace.library.version, 28)
        XCTAssertEqual(workspace.selected?.adjustments.localBrushSettings(for: .saturation).opacity, 0.55)
        XCTAssertTrue(try XCTUnwrap(workspace.selected).adjustments.localBrushSettings(for: .definition).inverted)

        workspace.undoEdit()
        XCTAssertFalse(try XCTUnwrap(workspace.selected).adjustments.localBrushSettings(for: .definition).inverted)
        workspace.undoEdit()
        XCTAssertEqual(try XCTUnwrap(workspace.selected).adjustments.localBrushSettings(for: .saturation).opacity, 1)
        workspace.redoEdit()
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushSettings(for: .saturation).opacity, 0.55)
        XCTAssertTrue(try XCTUnwrap(workspace.selected).adjustments.localBrushSettings(for: .definition).inverted)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.library.version, 28)
        XCTAssertEqual(reopened.selected?.adjustments.localBrushes, [saturation, definition])
        XCTAssertEqual(reopened.selected?.adjustments.localBrushSettings(for: .saturation).opacity, 0.55)
        XCTAssertTrue(try XCTUnwrap(reopened.selected).adjustments.localBrushSettings(for: .definition).inverted)

        let edited = try XCTUnwrap(reopened.selected)
        let original = try repository.availableOriginalURL(edited)
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: edited.adjustments,
                                                                 maximum: nil, revision: 0)
        XCTAssertNotEqual(try pixels(viewer.image), try pixels(Renderer.render(original,
                                                                                adjustments: Adjustments())))
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Local-Effects.png")
        try Renderer.export(edited, repository: repository, to: output, options: options)
        XCTAssertEqual(try pixels(viewer.image), try pixels(decode(output)))
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
        var originalOptions = ExportOptions()
        originalOptions.format = .original
        let originalCopy = folder.appendingPathComponent("Original.png")
        try Renderer.export(edited, repository: repository, to: originalCopy, options: originalOptions)
        XCTAssertEqual(try LibraryRepository.digest(originalCopy), sourceDigest)
    }

    private func writeFixture(_ url: URL) throws {
        let width = 192, height = 112
        var values = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let side = x < width / 2 ? 0 : 22
                let texture = (x + y).isMultiple(of: 2) ? -7 : 7
                let offset = (y * width + x) * 4
                values[offset] = UInt8(68 + side + texture)
                values[offset + 1] = UInt8(105 + side + texture)
                values[offset + 2] = UInt8(145 + side + texture)
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(values) as CFData))
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
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
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return result
    }
}
