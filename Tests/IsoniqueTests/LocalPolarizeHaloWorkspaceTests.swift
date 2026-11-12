import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class LocalPolarizeHaloWorkspaceTests: XCTestCase {
    @MainActor
    func testUndoRedoPersistenceOrderedInstancesExportAndOriginalPreservation() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniquePolarizeHaloWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniquePolarizeHaloWorkspace-\(UUID().uuidString)"
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
        workspace.chooseBrush(.polarize)
        workspace.applyBrushStroke(stroke(.polarize), to: photoID)
        workspace.setLocalPolarizeSettings(LocalPolarizeSettings(intensity: 0.85))
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances(for: .polarize).first?
            .polarizeSettings, LocalPolarizeSettings())
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances(for: .polarize).first?
            .polarizeSettings, LocalPolarizeSettings(intensity: 0.85))

        workspace.chooseBrush(.haloReduction)
        workspace.applyBrushStroke(stroke(.haloReduction), to: photoID)
        let tightID = try XCTUnwrap(workspace.brushInstanceID)
        workspace.renameBrushInstance(tightID, to: "Tight halos")
        workspace.setLocalHaloReductionSettings(LocalHaloReductionSettings(amount: 1, radius: 0.01))
        workspace.duplicateBrushInstance(tightID)
        let broadID = try XCTUnwrap(workspace.brushInstanceID)
        workspace.renameBrushInstance(broadID, to: "Broad halos")
        workspace.setLocalHaloReductionSettings(LocalHaloReductionSettings(amount: 0.65, radius: 0.06))
        workspace.moveBrushInstance(broadID, by: -1)
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances(for: .haloReduction).map(\.id),
                       [broadID, tightID])
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances(for: .haloReduction).map(\.id),
                       [tightID, broadID])
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.localBrushInstances(for: .haloReduction).map(\.id),
                       [broadID, tightID])
        XCTAssertEqual(workspace.library.version, 33)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.library.version, 33)
        let polarize = try XCTUnwrap(reopened.selected).adjustments.localBrushInstances(for: .polarize)
        let halos = try XCTUnwrap(reopened.selected).adjustments.localBrushInstances(for: .haloReduction)
        XCTAssertEqual(polarize.first?.polarizeSettings, LocalPolarizeSettings(intensity: 0.85))
        XCTAssertEqual(halos.map(\.id), [broadID, tightID])
        XCTAssertEqual(halos.map(\.haloReductionSettings), [
            LocalHaloReductionSettings(amount: 0.65, radius: 0.06),
            LocalHaloReductionSettings(amount: 1, radius: 0.01),
        ])
        XCTAssertTrue(reopened.canUndo)

        let edited = try XCTUnwrap(reopened.selected)
        let original = try repository.availableOriginalURL(edited)
        let viewer = try await reopened.viewerRenderCache.frame(url: original, adjustments: edited.adjustments,
                                                                 maximum: nil, revision: 0)
        XCTAssertNotEqual(try pixels(viewer.image),
                          try pixels(Renderer.render(original, adjustments: Adjustments())))
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Polarize-Halo.png")
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

    private func stroke(_ adjustment: LocalBrushAdjustment) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: adjustment, radius: 0.25, softness: 0.25,
            strength: 1, edgeAware: true,
            points: [BrushPoint(x: 0.25, y: 0.5), BrushPoint(x: 0.5, y: 0.5),
                     BrushPoint(x: 0.75, y: 0.5)])
    }

    private func writeFixture(_ url: URL) throws {
        let width = 192, height = 112
        var values = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let channels: (Int, Int, Int)
                if x < width / 2 {
                    let variation = (x + y).isMultiple(of: 2) ? -5 : 5
                    channels = (65 + variation, 130 + variation, 205 + variation)
                } else if x == width / 2 {
                    channels = (255, 255, 255)
                } else if x == width / 2 + 1 {
                    channels = (0, 0, 0)
                } else {
                    channels = (205, 135, 70)
                }
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
