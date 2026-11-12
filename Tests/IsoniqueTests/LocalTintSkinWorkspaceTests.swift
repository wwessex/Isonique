import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class LocalTintSkinWorkspaceTests: XCTestCase {
    @MainActor
    func testSettingsUndoRedoPersistenceFullSizeExportAndOriginalPreservation() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueTintSkinWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueTintSkinWorkspace-\(UUID().uuidString)"
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
        workspace.chooseBrush(.tint)
        let tint = LocalBrushStroke(adjustment: .tint, radius: 0.24, softness: 0.35,
            strength: 1, edgeAware: true, points: [BrushPoint(x: 0.48, y: 0.5)])
        workspace.applyBrushStroke(tint, to: photoID)
        workspace.chooseBrush(.skinSmoothing)
        let skin = LocalBrushStroke(adjustment: .skinSmoothing, radius: 0.22, softness: 0.3,
            strength: 1, edgeAware: true, points: [BrushPoint(x: 0.52, y: 0.5)])
        workspace.applyBrushStroke(skin, to: photoID)
        let tintSettings = LocalTintSettings(hue: 215, saturation: 0.8)
        let skinSettings = LocalSkinSmoothingSettings(amount: 0.9, detailPreservation: 0.3)
        workspace.setLocalTintSettings(tintSettings)
        workspace.setLocalSkinSmoothingSettings(skinSettings)
        workspace.setBrushMaskOpacity(0.55, for: .tint)
        workspace.invertBrushMask(.skinSmoothing)
        XCTAssertEqual(workspace.history.undo.count, 6)
        XCTAssertEqual(workspace.library.version, 31)
        XCTAssertEqual(workspace.selected?.adjustments.localTintSettings, tintSettings)
        XCTAssertEqual(workspace.selected?.adjustments.localSkinSmoothingSettings, skinSettings)

        workspace.undoEdit()
        workspace.undoEdit()
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localSkinSmoothingSettings,
                       LocalSkinSmoothingSettings())
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localTintSettings, LocalTintSettings())
        workspace.redoEdit()
        workspace.redoEdit()
        workspace.redoEdit()
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localTintSettings, tintSettings)
        XCTAssertEqual(workspace.selected?.adjustments.localSkinSmoothingSettings, skinSettings)
        XCTAssertEqual(workspace.selected?.adjustments.localBrushSettings(for: .tint).opacity, 0.55)
        XCTAssertTrue(try XCTUnwrap(workspace.selected).adjustments
            .localBrushSettings(for: .skinSmoothing).inverted)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.library.version, 31)
        XCTAssertEqual(reopened.selected?.adjustments.localBrushes, [tint, skin])
        XCTAssertEqual(reopened.selected?.adjustments.localTintSettings, tintSettings)
        XCTAssertEqual(reopened.selected?.adjustments.localSkinSmoothingSettings, skinSettings)

        let edited = try XCTUnwrap(reopened.selected)
        let original = try repository.availableOriginalURL(edited)
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: edited.adjustments,
                                                                 maximum: nil, revision: 0)
        XCTAssertNotEqual(try pixels(viewer.image),
                          try pixels(Renderer.render(original, adjustments: Adjustments())))
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Local-Tint-Skin.png")
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
                let delta = (x + y).isMultiple(of: 2) ? -10 : 10
                let offset = (y * width + x) * 4
                let channels = x < width / 2
                    ? (190 + delta, 130 + delta, 100 + delta)
                    : (70 + delta, 160 + delta, 90 + delta)
                values[offset] = UInt8(channels.0)
                values[offset + 1] = UInt8(channels.1)
                values[offset + 2] = UInt8(channels.2)
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
