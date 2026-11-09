import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class CurveSamplingTests: XCTestCase {
    func testAutomaticCurveClipsTailsAndAnchorPreservesCurrentMapping() throws {
        var bins = [Int](repeating: 0, count: 256)
        bins[0] = 1; bins[40] = 99; bins[200] = 99; bins[255] = 1
        var curve = try XCTUnwrap(ChannelCurve.automatic(from: bins))
        XCTAssertEqual(curve.points, [CurvePoint(input: 0, output: 0), CurvePoint(input: 40, output: 0),
                                      CurvePoint(input: 200, output: 255), CurvePoint(input: 255, output: 255)])
        let expected = Int((curve.value(at: 104.0 / 255) * 255).rounded())
        let index = try XCTUnwrap(curve.anchor(input: 104))
        XCTAssertEqual(curve.points[index], CurvePoint(input: 104, output: expected))
        let anchored = curve
        XCTAssertEqual(curve.anchor(input: 104), index)
        XCTAssertEqual(curve.anchor(input: 0), 0)
        XCTAssertEqual(curve, anchored)
        XCTAssertNil(curve.anchor(input: 256))
        for input in 1...16 { curve.anchor(input: input) }
        XCTAssertEqual(curve.points.count, ChannelCurve.pointLimit)
        XCTAssertNil(curve.anchor(input: 99))
        XCTAssertEqual(curve.anchor(input: 104), curve.points.firstIndex { $0.input == 104 })
        bins = [Int](repeating: 0, count: 256)
        bins[128] = 200
        XCTAssertNil(ChannelCurve.automatic(from: bins))
    }

    func testLoupeSampleUsesGeometryAndPreCurveStage() throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Stripes.png")
        try writeFixture(source, colors: [[64, 96, 40, 255], [160, 200, 130, 255], [0, 0, 0, 0]])
        var recipe = Adjustments()
        XCTAssertNil(try Renderer.sampleCurveInput(source, adjustments: recipe, channel: .red,
                                                  viewerPoint: CGPoint(x: 0.9, y: 0.5)))
        recipe.flipHorizontal = true
        recipe.crop = PhotoCrop(x: 1.0 / 3, y: 0, width: 1.0 / 3, height: 1)
        var levels = LevelValues()
        levels.blackPoint = 0.2
        recipe.setLevels(levels, for: .red)
        var curve = ChannelCurve.identity
        curve.insertPoint(input: 136, output: 220)
        recipe.setCurve(curve, for: .red)
        let target = CGPoint(x: 0.5, y: 0.5)
        XCTAssertEqual(try Renderer.sampleCurveInput(source, adjustments: recipe, channel: .red, viewerPoint: target), 136)
        XCTAssertEqual(try Renderer.sampleCurveInput(source, adjustments: recipe, channel: .green, viewerPoint: target), 200)
        let luminance = try XCTUnwrap(Renderer.sampleCurveInput(source, adjustments: recipe, channel: .luminance,
                                                                viewerPoint: target))
        let histogram = try Renderer.adjustmentHistograms(source, adjustments: recipe).channelCurves
        XCTAssertGreaterThan(histogram.luminance[luminance], 0)
        XCTAssertGreaterThan(histogram.red[136], 0)
        recipe.setCurve(curve, for: .luminance)
        XCTAssertEqual(try Renderer.sampleCurveInput(source, adjustments: recipe, channel: .luminance,
                                                     viewerPoint: target), luminance)
    }

    @MainActor
    func testAutomaticAndLoupeEditsPersistUndoOnceAndMatchFullSizePNG() async throws {
        let folder = try makeFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Gradient.png")
        try writeFixture(source, colors: [[40, 55, 70, 255], [90, 100, 120, 255], [160, 180, 200, 255]])
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        let initial = try XCTUnwrap(library.photos.first)
        let suite = "IsoniqueCurveSampling-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)

        let firstInput = try Renderer.adjustmentHistograms(source, adjustments: initial.adjustments).channelCurves
        workspace.applyAutoCurves(.combined, input: firstInput, for: initial)
        let combined = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(combined.adjustments.curve(for: .red), .identity)
        XCTAssertNotEqual(combined.adjustments.curve(for: .luminance), .identity)
        workspace.applyAutoCurves(.separate, input: firstInput, for: initial)
        XCTAssertEqual(workspace.selected, combined)
        let secondInput = try Renderer.adjustmentHistograms(source, adjustments: combined.adjustments).channelCurves
        workspace.applyAutoCurves(.separate, input: secondInput, for: combined)
        let separated = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(workspace.history.undo.count, 2)
        XCTAssertEqual(separated.adjustments.curve(for: .luminance), combined.adjustments.curve(for: .luminance))
        for channel: CurveChannel in [.red, .green, .blue] {
            XCTAssertNotEqual(separated.adjustments.curve(for: channel), .identity)
        }

        workspace.startCurveSampling(.red, photoID: initial.id)
        let request = try XCTUnwrap(workspace.activeCurveSampling)
        let original = try repository.availableOriginalURL(initial)
        let work = CurveSampleWork(request: request, point: CGPoint(x: 0.5, y: 0.5))
        let sampledInput = try await work.load(from: original)
        XCTAssertEqual(sampledInput, 90)
        workspace.finishCurveSampling(request, input: sampledInput)
        let anchored = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(workspace.history.undo.count, 3)
        XCTAssertEqual(workspace.curvePointSelection?.input, 90)
        XCTAssertNil(workspace.activeCurveSampling)
        workspace.startCurveSampling(.red, photoID: initial.id)
        let duplicate = try XCTUnwrap(workspace.activeCurveSampling)
        workspace.finishCurveSampling(request, input: 91)
        XCTAssertEqual(workspace.activeCurveSampling, duplicate)
        workspace.finishCurveSampling(duplicate, input: sampledInput)
        XCTAssertEqual(workspace.history.undo.count, 3)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.library.version, 5)
        XCTAssertEqual(reopened.selected, anchored)
        for expected in [separated, combined, initial] {
            reopened.undoEdit()
            XCTAssertEqual(reopened.selected, expected)
        }
        for expected in [combined, separated, anchored] {
            reopened.redoEdit()
            XCTAssertEqual(reopened.selected, expected)
        }

        let preview = try await reopened.viewerRenderCache.frame(url: original, adjustments: anchored.adjustments,
                                                                  maximum: nil, revision: 0)
        var options = ExportOptions()
        options.format = .png
        let output = folder.appendingPathComponent("Export.png")
        try Renderer.export(anchored, repository: repository, to: output, options: options)
        let exported = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(exported, 0, nil))
        XCTAssertEqual(image.width, 600)
        XCTAssertEqual(image.height, 320)
        XCTAssertEqual(try pixels(image), try pixels(preview.image))
        XCTAssertEqual(try LibraryRepository.digest(original), initial.sha256)
        XCTAssertEqual(try LibraryRepository.digest(source), initial.sha256)
    }

    private func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueCurveSampling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func writeFixture(_ url: URL, colors: [[UInt8]]) throws {
        let width = 600, height = 320
        let row = (0..<width).flatMap { colors[$0 * colors.count / width] }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(Array(repeating: row, count: height).joined()) as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        let image = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
                                         bitsPerPixel: 32, bytesPerRow: width * 4, space: space, bitmapInfo: info,
                                         provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: space, bitmapInfo: info))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4)
    }
}
