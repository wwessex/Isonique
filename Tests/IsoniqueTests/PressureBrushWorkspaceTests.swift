import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class PressureBrushWorkspaceTests: XCTestCase {
    func testPressurePreferencesAndCanvasSamplesPersistWithoutChangingFallback() throws {
        let suite = "IsoniquePressurePreferences-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let mapping = BrushPressureMapping(sizeCurve: .firm, strengthCurve: .soft,
                                           minimumSize: 0.35, minimumStrength: 0.18)
        BrushPressurePreferences.save(mapping, to: preferences)
        XCTAssertEqual(BrushPressurePreferences.load(from: preferences), mapping)
        XCTAssertEqual(mapping.sample(pressure: 0.2, isTablet: false),
                       BrushPressureSample(radiusScale: 1, strengthScale: 1))

        let geometry = PhotoGeometry(width: 200, height: 100, adjustments: Adjustments())
        let points = BrushCanvas.sourcePoints([
            BrushCanvasPoint(location: CGPoint(x: 20, y: 30), radiusScale: 0.35, strengthScale: 0.18),
            BrushCanvasPoint(location: CGPoint(x: 80, y: 30), radiusScale: 0.9, strengthScale: 0.75),
        ], displayedSize: CGSize(width: 100, height: 50), geometry: geometry)
        XCTAssertEqual(points.map(\.radiusScale), [0.35, 0.9])
        XCTAssertEqual(points.map(\.strengthScale), [0.18, 0.75])
        XCTAssertEqual(points.map(\.x), [0.2, 0.8])
        XCTAssertTrue(BrushInputClassifier.isTablet(subtype: .tabletPoint,
                                                     pointingDeviceType: .unknown))
        let ordinary = NSEvent.EventSubtype.mouseEvent
        XCTAssertTrue(BrushInputClassifier.isTablet(subtype: ordinary, pointingDeviceType: .pen))
        XCTAssertTrue(BrushInputClassifier.isTablet(subtype: ordinary, pointingDeviceType: .eraser))
        XCTAssertFalse(BrushInputClassifier.isTablet(subtype: ordinary, pointingDeviceType: .unknown))
    }

    @MainActor
    func testUndoRedoPersistencePreviewExportAndOriginalPreservation() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniquePressureBrushWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniquePressureBrushWorkspace-\(UUID().uuidString)"
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

        let stroke = LocalBrushStroke(adjustment: .dodge, radius: 0.18, softness: 0.35,
            strength: 0.8, edgeAware: true, points: [
                BrushPoint(x: 0.25, y: 0.5, radiusScale: 0.3, strengthScale: 0.2),
                BrushPoint(x: 0.5, y: 0.5, radiusScale: 0.6, strengthScale: 0.55),
                BrushPoint(x: 0.75, y: 0.5, radiusScale: 1, strengthScale: 1),
            ])
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.selection = photoID
        workspace.chooseBrush(.dodge)
        workspace.applyBrushStroke(stroke, to: photoID)
        XCTAssertEqual(workspace.library.version, 34)
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances(for: .dodge).first?.strokes,
                       [stroke])
        workspace.undoEdit()
        XCTAssertTrue(workspace.selected?.adjustments.localBrushInstances(for: .dodge).isEmpty == true)
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances(for: .dodge).first?.strokes,
                       [stroke])

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.library.version, 34)
        XCTAssertEqual(reopened.selected?.adjustments.localBrushInstances(for: .dodge).first?.strokes,
                       [stroke])
        let edited = try XCTUnwrap(reopened.selected)
        let original = try repository.availableOriginalURL(edited)
        LocalBrushMaskCache.shared.removeAll()
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: edited.adjustments,
                                                                 maximum: nil, revision: 0)
        XCTAssertNotEqual(try pixels(viewer.image),
                          try pixels(Renderer.render(original, adjustments: Adjustments())))
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Pressure.png")
        try Renderer.export(edited, repository: repository, to: output, options: options)
        XCTAssertEqual(try pixels(viewer.image), try pixels(decode(output)))
        let cacheStats = LocalBrushMaskCache.shared.statistics()
        XCTAssertGreaterThanOrEqual(cacheStats.exactHits, 1,
            "The edited export should reuse the full-size Viewer source-space mask")
        XCTAssertEqual(cacheStats.rasterizedStrokes, 1)
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
                let offset = (y * width + x) * 4
                let value = UInt8(85 + (x + y) % 40)
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
}
