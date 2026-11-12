import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class LocalBrushInstanceWorkspaceTests: XCTestCase {
    @MainActor
    func testInstanceActionsUndoRedoPersistenceExportAndOriginalPreservation() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueBrushInstanceWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueBrushInstanceWorkspace-\(UUID().uuidString)"
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
        let stroke = LocalBrushStroke(adjustment: .tint, radius: 0.24, softness: 0.3,
            strength: 1, edgeAware: true, points: [BrushPoint(x: 0.5, y: 0.5)])
        workspace.applyBrushStroke(stroke, to: photoID)
        let warmID = try XCTUnwrap(workspace.brushInstanceID)
        workspace.renameBrushInstance(warmID, to: "Warm face")
        workspace.setLocalTintSettings(LocalTintSettings(hue: 18, saturation: 0.6))
        workspace.duplicateBrushInstance(warmID)
        let coolID = try XCTUnwrap(workspace.brushInstanceID)
        workspace.renameBrushInstance(coolID, to: "Cool finish")
        workspace.setLocalTintSettings(LocalTintSettings(hue: 220, saturation: 0.35))
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances.map(\.name),
                       ["Warm face", "Cool finish"])
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances[0].tintSettings.hue, 18)
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances[1].tintSettings.hue, 220)

        workspace.moveBrushInstance(coolID, by: -1)
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances.map(\.id), [coolID, warmID])
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances.map(\.id), [warmID, coolID])
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances.map(\.id), [coolID, warmID])

        workspace.setBrushInstanceEnabled(coolID, enabled: false)
        XCTAssertFalse(try XCTUnwrap(workspace.selected).adjustments.localBrushInstances[0].enabled)
        workspace.undoEdit()
        XCTAssertTrue(try XCTUnwrap(workspace.selected).adjustments.localBrushInstances[0].enabled)
        workspace.redoEdit()
        XCTAssertFalse(try XCTUnwrap(workspace.selected).adjustments.localBrushInstances[0].enabled)
        workspace.setBrushInstanceEnabled(coolID, enabled: true)

        workspace.createBrushInstance(.tint)
        let temporaryID = try XCTUnwrap(workspace.brushInstanceID)
        workspace.renameBrushInstance(temporaryID, to: "Temporary")
        workspace.deleteBrushInstance(temporaryID)
        XCTAssertNil(workspace.selected?.adjustments.localBrushInstance(id: temporaryID))
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstance(id: temporaryID)?.name, "Temporary")
        workspace.redoEdit()
        XCTAssertNil(workspace.selected?.adjustments.localBrushInstance(id: temporaryID))
        XCTAssertEqual(workspace.library.version, 32)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        let instances = try XCTUnwrap(reopened.selected).adjustments.localBrushInstances
        XCTAssertEqual(instances.map(\.id), [coolID, warmID])
        XCTAssertEqual(instances.map(\.name), ["Cool finish", "Warm face"])
        XCTAssertTrue(instances.allSatisfy(\.enabled))
        XCTAssertTrue(reopened.canUndo)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.localBrushInstance(id: temporaryID)?.name, "Temporary")
        reopened.redoEdit()
        XCTAssertNil(reopened.selected?.adjustments.localBrushInstance(id: temporaryID))

        let edited = try XCTUnwrap(reopened.selected)
        let original = try repository.availableOriginalURL(edited)
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: edited.adjustments,
                                                                 maximum: nil, revision: 0)
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Instances.png")
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
        let width = 160, height = 96
        var values = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let delta = (x + y).isMultiple(of: 2) ? -6 : 6
                values[offset] = UInt8(154 + delta)
                values[offset + 1] = UInt8(118 + delta)
                values[offset + 2] = UInt8(96 + delta)
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
