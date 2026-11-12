import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class AdvancedLocalBrushWorkspaceTests: XCTestCase {
    @MainActor
    func testUndoPersistenceOverlayPixelZoomAndFullSizeExportConsistency() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueAdvancedBrushWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueAdvancedBrushWorkspace-\(UUID().uuidString)"
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
        workspace.chooseBrush(.dodge)
        let stroke = LocalBrushStroke(adjustment: .dodge, radius: 0.2, softness: 0.35,
            strength: 1, edgeAware: true, points: [BrushPoint(x: 0.4, y: 0.5)])
        workspace.applyBrushStroke(stroke, to: photoID)
        workspace.setBrushMaskOpacity(0.45, for: .dodge)
        workspace.invertBrushMask(.dodge)
        XCTAssertEqual(workspace.history.undo.count, 3)
        XCTAssertEqual(workspace.library.version, 32)
        XCTAssertEqual(workspace.selected?.adjustments.localBrushSettings(for: .dodge),
                       LocalBrushMaskSettings(opacity: 0.45, inverted: true))

        workspace.undoEdit()
        XCTAssertFalse(try XCTUnwrap(workspace.selected).adjustments.localBrushSettings(for: .dodge).inverted)
        workspace.undoEdit()
        XCTAssertEqual(try XCTUnwrap(workspace.selected).adjustments.localBrushSettings(for: .dodge).opacity, 1)
        workspace.redoEdit()
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushSettings(for: .dodge),
                       LocalBrushMaskSettings(opacity: 0.45, inverted: true))

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.library.version, 32)
        XCTAssertEqual(reopened.selected?.adjustments.effectiveLocalBrushInstances.flatMap(\.strokes), [stroke])
        XCTAssertEqual(reopened.selected?.adjustments.localBrushSettings(for: .dodge),
                       LocalBrushMaskSettings(opacity: 0.45, inverted: true))
        reopened.clearBrushMask(.dodge)
        XCTAssertTrue(try XCTUnwrap(reopened.selected).adjustments.effectiveLocalBrushInstances
            .flatMap(\.strokes).isEmpty)
        XCTAssertEqual(try XCTUnwrap(reopened.selected).adjustments.localBrushSettings(for: .dodge),
                       LocalBrushMaskSettings())
        reopened.undoEdit()

        let brushed = try XCTUnwrap(reopened.selected)
        let original = try repository.availableOriginalURL(brushed)
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: brushed.adjustments,
                                                                 maximum: nil, revision: 0)
        let fitPoint = try XCTUnwrap(BrushCanvas.sourcePoints([CGPoint(x: 48, y: 28)],
            displayedSize: CGSize(width: 96, height: 56), geometry: viewer.geometry).first)
        let pixelZoomPoint = try XCTUnwrap(BrushCanvas.sourcePoints([CGPoint(x: 96, y: 56)],
            displayedSize: CGSize(width: 192, height: 112), geometry: viewer.geometry).first)
        XCTAssertEqual(fitPoint.x, pixelZoomPoint.x, accuracy: 0.000_001)
        XCTAssertEqual(fitPoint.y, pixelZoomPoint.y, accuracy: 0.000_001)

        let overlay = try XCTUnwrap(Renderer.localBrushMaskOverlay(original, adjustments: brushed.adjustments,
                                                                    adjustment: .dodge))
        XCTAssertEqual(overlay.width, viewer.image.width)
        XCTAssertEqual(overlay.height, viewer.image.height)
        XCTAssertLessThan(try alpha(overlay, x: 0.4, y: 0.5), 5)
        XCTAssertGreaterThan(try alpha(overlay, x: 0.9, y: 0.5), 50)

        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Advanced-Brush.png")
        try Renderer.export(brushed, repository: repository, to: output, options: options)
        XCTAssertEqual(try pixels(viewer.image), try pixels(decode(output)),
                       "Viewer-only mask colour must stay out of edited exports")
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
        var originalOptions = ExportOptions()
        originalOptions.format = .original
        let originalCopy = folder.appendingPathComponent("Original.png")
        try Renderer.export(brushed, repository: repository, to: originalCopy, options: originalOptions)
        XCTAssertEqual(try LibraryRepository.digest(originalCopy), sourceDigest)
    }

    private func writeFixture(_ url: URL) throws {
        let width = 192, height = 112
        var values = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = x < width / 2 ? 48 : 205
                let offset = (y * width + x) * 4
                values[offset] = value
                values[offset + 1] = value
                values[offset + 2] = value
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

    private func alpha(_ image: CGImage, x: Double, y: Double) throws -> Int {
        let values = try pixels(image)
        let px = min(image.width - 1, max(0, Int(x * Double(image.width))))
        let py = min(image.height - 1, max(0, Int(y * Double(image.height))))
        return Int(values[(py * image.width + px) * 4 + 3])
    }
}
