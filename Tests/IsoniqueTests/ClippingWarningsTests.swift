import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import IsoniqueCore
@testable import Isonique

final class ClippingWarningsTests: XCTestCase {
    private let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                                        CGBitmapInfo.byteOrder32Big.rawValue)
    private let clear: [UInt8] = [0, 0, 0, 0]
    private let hot: [UInt8] = [166, 21, 21, 166]
    private let cold: [UInt8] = [21, 73, 166, 166]
    private let mixed: [UInt8] = [153, 21, 153, 166]

    func testDefaultThresholdsIndependentWarningsAndTransparency() throws {
        let source = try bitmap([
            [130, 255, 130, 255], [130, 130, 0, 255], [255, 130, 0, 255],
            [254, 128, 1, 255], [128, 64, 64, 128], [0, 64, 64, 128],
            [64, 64, 64, 128], clear
        ], width: 4)
        var settings = ClippingSettings()
        XCTAssertNil(try ClippingOverlay.make(from: source, settings: settings))
        settings.highlights = true
        XCTAssertEqual(try overlayPixels(source, settings), [hot, clear, hot, clear, [83, 10, 10, 83], clear, clear, clear])
        settings.shadows = true
        XCTAssertEqual(try overlayPixels(source, settings), [hot, cold, mixed, clear, [83, 10, 10, 83], [10, 36, 83, 83], clear, clear])
        settings.highlights = false
        XCTAssertEqual(try overlayPixels(source, settings), [clear, cold, cold, clear, clear, [10, 36, 83, 83], clear, clear])
    }

    func testCustomThresholdsAreInclusiveAndPreservePixelPositions() throws {
        let source = try bitmap([
            [204, 128, 128, 255], [203, 128, 128, 255], [128, 51, 128, 255],
            [128, 52, 128, 255], [128, 51, 204, 255], [128, 128, 128, 255]
        ], width: 3)
        var settings = ClippingSettings()
        settings.both = true
        settings.highlightThreshold = 80
        settings.shadowThreshold = 20
        XCTAssertEqual(try overlayPixels(source, settings), [hot, clear, cold, clear, mixed, clear])
        settings.highlightThreshold = 81
        settings.shadowThreshold = 19
        XCTAssertEqual(try overlayPixels(source, settings), Array(repeating: clear, count: 6))
    }

    @MainActor
    func testViewerWarningsAndThresholdsPersistOutsideCatalogue() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let suite = "IsoniqueClippingTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        XCTAssertFalse(workspace.clipping.enabled)
        XCTAssertEqual(workspace.clipping.highlightThreshold, 100)
        XCTAssertEqual(workspace.clipping.shadowThreshold, 0)
        workspace.clipping.highlights = true
        XCTAssertFalse(workspace.clipping.both)
        XCTAssertFalse(workspace.clipping.shadows)
        workspace.clipping.both = true
        XCTAssertTrue(workspace.clipping.highlights && workspace.clipping.shadows)
        workspace.clipping.shadows = false
        workspace.clipping.highlightThreshold = 92
        workspace.clipping.shadowThreshold = 7
        XCTAssertFalse(workspace.canUndo)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.clipping, workspace.clipping)
        reopened.clipping.both = false
        XCTAssertFalse(reopened.clipping.enabled)
        XCTAssertEqual(reopened.clipping.highlightThreshold, 92)
        XCTAssertEqual(reopened.clipping.shadowThreshold, 7)
        reopened.clipping.highlights = true
        reopened.clipping.resetThresholds()
        XCTAssertTrue(reopened.clipping.thresholdsAreDefault)
        XCTAssertTrue(reopened.clipping.highlights)
    }

    @MainActor
    func testViewerWarningsUseEditedPixelsAndLeaveExportsUnchanged() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let source = folder.appendingPathComponent("Fixture.png")
        let image = try bitmap([[224, 120, 120, 255], [28, 120, 120, 255], [120, 120, 120, 255]], width: 3)
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments.blackPoint = 0.12
        library.photos[0].adjustments.whitePoint = 0.85
        try repository.save(library)
        let suite = "IsoniqueClippingExportTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        let photo = try XCTUnwrap(workspace.selected)
        let original = try repository.availableOriginalURL(photo)
        let rendered = try Renderer.render(original, adjustments: photo.adjustments)
        let preview = try ViewerImage(rendered, proofProfile: nil)
        let profile = try XCTUnwrap(CGColorSpace(name: CGColorSpace.displayP3)?.copyICCData()) as Data
        let proofedPreview = try ViewerImage(rendered, proofProfile: profile)
        XCTAssertTrue(proofedPreview.rendered === rendered)
        XCTAssertFalse(proofedPreview.display === rendered)

        var options = ExportOptions()
        for format in [ExportFormat.png, .jpeg, .tiff, .heif, .original] {
            workspace.clipping.both = false
            options.format = format
            let suffix = format == .original ? "png" : format.suffix
            let before = folder.appendingPathComponent("Before-\(format).\(suffix)")
            let after = folder.appendingPathComponent("After-\(format).\(suffix)")
            try Renderer.export(photo, repository: repository, to: before, options: options)
            workspace.clipping.both = true
            XCTAssertEqual(try overlayPixels(image, workspace.clipping), [clear, clear, clear])
            XCTAssertEqual(try overlayPixels(preview.rendered, workspace.clipping), [hot, cold, clear])
            XCTAssertEqual(try overlayPixels(proofedPreview.rendered, workspace.clipping), [hot, cold, clear])
            try Renderer.export(try XCTUnwrap(workspace.selected), repository: repository, to: after, options: options)
            XCTAssertEqual(try pixels(decode(before)), try pixels(decode(after)))
            if format == .png { XCTAssertEqual(try pixels(decode(after)), try pixels(rendered)) }
            if format == .original { XCTAssertEqual(try Data(contentsOf: after), try Data(contentsOf: source)) }
        }
    }

    private func overlayPixels(_ source: CGImage, _ settings: ClippingSettings) throws -> [[UInt8]] {
        let overlay = try XCTUnwrap(ClippingOverlay.make(from: source, settings: settings))
        XCTAssertEqual(overlay.width, source.width)
        XCTAssertEqual(overlay.height, source.height)
        return try pixels(overlay)
    }

    private func bitmap(_ samples: [[UInt8]], width: Int) throws -> CGImage {
        let provider = try XCTUnwrap(CGDataProvider(data: Data(samples.flatMap { $0 }) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: samples.count / width, bitsPerComponent: 8,
                                     bitsPerPixel: 32, bytesPerRow: width * 4,
                                     space: XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
                                     bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                                     shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixels(_ image: CGImage) throws -> [[UInt8]] {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                             space: space, bitmapInfo: bitmapInfo.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<(image.width * image.height)).map { Array(UnsafeBufferPointer(start: bytes + $0 * 4, count: 4)) }
    }

    private func decode(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueClipping-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }
}
