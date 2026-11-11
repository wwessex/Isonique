import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class RedEyeWorkspaceTests: XCTestCase {
    @MainActor
    func testMultipleEyesUndoRedoPersistenceViewerExportAndOriginalPreservation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueRedEyeWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueRedEyeWorkspace-\(UUID().uuidString)"
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
        workspace.chooseRedEyeCorrection()
        XCTAssertEqual(workspace.tool, .redEye)
        workspace.placeRedEye(BrushPoint(x: 0.32, y: 0.5), radius: 0.07, darkness: 0.4, in: photoID)
        workspace.beginNewRedEye()
        workspace.placeRedEye(BrushPoint(x: 0.68, y: 0.5), radius: 0.08, darkness: 0.65, in: photoID)
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.count, 2)
        XCTAssertEqual(workspace.history.undo.count, 2)
        let secondID = try XCTUnwrap(workspace.selectedRedEyeID)

        workspace.setSelectedRedEyeRadius(0.1)
        workspace.setSelectedRedEyeDarkness(0.8)
        workspace.placeRedEye(BrushPoint(x: 0.69, y: 0.49), radius: 0.1, darkness: 0.8, in: photoID)
        XCTAssertEqual(workspace.history.undo.count, 5)
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.last?.radius, 0.1)
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.last?.darkness, 0.8)
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.last?.center, BrushPoint(x: 0.69, y: 0.49))
        workspace.undoEdit()
        XCTAssertEqual(workspace.tool, .redEye)
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.last?.center, BrushPoint(x: 0.68, y: 0.5))
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.last?.center, BrushPoint(x: 0.69, y: 0.49))
        workspace.deleteSelectedRedEye()
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.count, 1)
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.count, 2)
        XCTAssertEqual(workspace.selected?.adjustments.redEyeCorrections.last?.id, secondID)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.library.version, 25)
        XCTAssertEqual(reopened.selected?.adjustments.redEyeCorrections.count, 2)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.redEyeCorrections.last?.center, BrushPoint(x: 0.68, y: 0.5))
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.redEyeCorrections.last?.center, BrushPoint(x: 0.69, y: 0.49))

        let corrected = try XCTUnwrap(reopened.selected)
        let original = try repository.availableOriginalURL(corrected)
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: corrected.adjustments,
                                                                 maximum: nil, revision: 0)
        XCTAssertNotEqual(try pixels(viewer.image), try pixels(Renderer.render(original, adjustments: Adjustments())))
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Corrected.png")
        try Renderer.export(corrected, repository: repository, to: output, options: options)
        XCTAssertEqual(try pixels(viewer.image), try pixels(decode(output)))
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
        var originalOptions = ExportOptions()
        originalOptions.format = .original
        let originalCopy = folder.appendingPathComponent("Original.png")
        try Renderer.export(corrected, repository: repository, to: originalCopy, options: originalOptions)
        XCTAssertEqual(try LibraryRepository.digest(originalCopy), sourceDigest)
    }

    private func writeFixture(_ url: URL) throws {
        let width = 160, height = 100
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                              bytesPerRow: width * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                  CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(red: 0.45, green: 0.38, blue: 0.32, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.95, green: 0.08, blue: 0.06, alpha: 1)
        context.fillEllipse(in: CGRect(x: 46, y: 44, width: 11, height: 11))
        context.fillEllipse(in: CGRect(x: 103, y: 44, width: 11, height: 11))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
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
