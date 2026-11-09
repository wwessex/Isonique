import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class ChannelCurvesTests: XCTestCase {
    func testPointsInterpolateAndRemainOrdered() throws {
        var curve = ChannelCurve.identity
        let mid = try XCTUnwrap(curve.insertPoint(input: 128, output: 200))
        XCTAssertEqual(curve.value(at: 64.0 / 255), 100.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(curve.value(at: 128.0 / 255), 200.0 / 255, accuracy: 1e-12)
        XCTAssertNil(curve.insertPoint(input: 128, output: 10))
        curve.movePoint(at: mid, input: 300, output: 500)
        XCTAssertEqual(curve.points[mid], CurvePoint(input: 254, output: 255))
        curve.movePoint(at: 0, input: 100, output: 10)
        XCTAssertEqual(curve.points[0], CurvePoint(input: 0, output: 10))
        curve.removePoint(at: 0)
        XCTAssertEqual(curve.points.count, 3)
        curve.removePoint(at: mid)
        XCTAssertEqual(try JSONDecoder().decode(ChannelCurve.self, from: JSONEncoder().encode(curve)), curve)
        let invalid = Data(#"{"points":[{"input":0,"output":0},{"input":0,"output":20},{"input":255,"output":255}]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ChannelCurve.self, from: invalid))
    }

    func testRGBIsolationAndLuminancePreserveAlphaAndNeutrality() throws {
        let fixture: [UInt8] = [128, 128, 128, 255, 220, 120, 30, 255, 64, 64, 64, 128, 0, 0, 0, 0]
        let image = try bitmap(fixture, width: 4)
        let identity = (0...255).map { Double($0) / 255 }
        var settings = Adjustments()
        settings.setCurve(raisedMidtones, for: .red)
        let red = try TonalTools.applying(image, table: identity, curves: settings.channelCurves)
        let rgb = try pixels(red)
        XCTAssertEqual(Array(rgb[0..<4]), [190, 128, 128, 255])
        XCTAssertEqual(Array(rgb[5..<8]), [120, 30, 255])
        XCTAssertEqual(Array(rgb[8..<12]), [95, 64, 64, 128])
        XCTAssertEqual(Array(rgb[12..<16]), [0, 0, 0, 0])
        settings.setCurve(.identity, for: .red)
        XCTAssertNil(settings.channelCurves)
        settings.setCurve(raisedMidtones, for: .luminance)
        let luminance = try TonalTools.applying(image, table: identity, curves: settings.channelCurves)
        let mapped = try pixels(luminance)
        XCTAssertEqual(Double(mapped[0]), 190, accuracy: 1)
        XCTAssertEqual(mapped[0], mapped[1])
        XCTAssertEqual(mapped[1], mapped[2])
        XCTAssertGreaterThan(mapped[4], mapped[5])
        XCTAssertGreaterThan(mapped[5], mapped[6])
        XCTAssertGreaterThan(mapped[5], fixture[5])
        XCTAssertEqual(mapped[11], 128)
        XCTAssertEqual(Array(mapped[12..<16]), [0, 0, 0, 0])
    }

    func testSharedPreviewExportAndCatalogueVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueCurves-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Source.png")
        let image = try bitmap([64, 64, 64, 255, 128, 128, 128, 255, 190, 190, 190, 255, 255, 255, 255, 255], width: 2)
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let digest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        XCTAssertNil(library.photos[0].adjustments.channelCurves)
        var recipe = Adjustments()
        recipe.setCurve(raisedMidtones, for: .green)
        recipe.setCurve(raisedMidtones, for: .luminance)
        library.photos[0].adjustments = recipe
        XCTAssertThrowsError(try repository.save(library))
        library.upgradeForChannelCurves()
        XCTAssertEqual(library.version, 5)
        try repository.save(library)
        XCTAssertEqual(try repository.load().photos.first?.adjustments, recipe)
        var levels = LevelValues()
        levels.blackPoint = 0.16
        levels.whitePoint = 0.92
        levels.gamma = 1.2
        recipe.setLevels(levels, for: .blue)
        library.photos[0].adjustments = recipe
        XCTAssertThrowsError(try repository.save(library))
        library.upgradeForChannelLevels()
        XCTAssertEqual(library.version, 6)
        try repository.save(library)
        let photo = try XCTUnwrap(repository.load().photos.first)
        XCTAssertEqual(photo.adjustments, recipe)
        XCTAssertEqual(recipe.stamping(onto: Adjustments(), groups: [.tone]), recipe)
        XCTAssertNil(recipe.stamping(onto: Adjustments(), groups: [.basic]).channelCurves)
        XCTAssertNil(recipe.stamping(onto: Adjustments(), groups: [.basic]).channelLevels)
        XCTAssertNil(AdjustmentPreset.natural.applying(to: recipe).channelCurves)
        XCTAssertNil(AdjustmentPreset.natural.applying(to: recipe).channelLevels)

        let original = try repository.availableOriginalURL(photo)
        let preview = try Renderer.render(original, adjustments: photo.adjustments)
        XCTAssertNotEqual(try pixels(preview), try pixels(image))
        var options = ExportOptions()
        options.format = .png
        let output = root.appendingPathComponent("Edited.png")
        try Renderer.export(photo, repository: repository, to: output, options: options)
        let exported = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(try pixels(XCTUnwrap(CGImageSourceCreateImageAtIndex(exported, 0, nil))), try pixels(preview))
        XCTAssertEqual(try LibraryRepository.digest(original), digest)
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
    }

    func testChannelLevelsClipAndRemapOnlySelectedChannelBeforeCurve() throws {
        var settings = Adjustments()
        var levels = LevelValues()
        levels.blackPoint = 0.25
        levels.whitePoint = 0.75
        levels.gamma = 2
        settings.setLevels(levels, for: .red)
        let source = try bitmap([32, 40, 75, 255, 128, 128, 128, 255, 240, 20, 90, 255], width: 3)
        let identity = (0...255).map { Double($0) / 255 }
        let output = try TonalTools.applying(source, table: identity, channelLevels: settings.channelLevels)
        XCTAssertEqual(try pixels(output), [0, 40, 75, 255, 181, 128, 128, 255, 255, 20, 90, 255])
        var curve = ChannelCurve.identity
        curve.insertPoint(input: 181, output: 90)
        settings.setCurve(curve, for: .red)
        let composited = try TonalTools.applying(source, table: identity, curves: settings.channelCurves,
                                                 channelLevels: settings.channelLevels)
        XCTAssertEqual(try pixels(composited), [0, 40, 75, 255, 90, 128, 128, 255, 255, 20, 90, 255])
        levels.blackPoint = 4
        levels.whitePoint = 0.5
        levels.gamma = .nan
        settings.setLevels(levels, for: .blue)
        let blue = settings.levels(for: .blue)
        XCTAssertEqual(blue.blackPoint, 0.99)
        XCTAssertEqual(blue.whitePoint, 1)
        XCTAssertEqual(blue.gamma, 1)
    }

    private var raisedMidtones: ChannelCurve {
        var curve = ChannelCurve.identity
        curve.insertPoint(input: 128, output: 190)
        return curve
    }

    private func bitmap(_ bytes: [UInt8], width: Int) throws -> CGImage {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
        return try XCTUnwrap(CGImage(width: width, height: bytes.count / (width * 4), bitsPerComponent: 8,
                                     bitsPerPixel: 32, bytesPerRow: width * 4, space: space, bitmapInfo: info,
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: space, bitmapInfo: info))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(Data(bytes: try XCTUnwrap(context.data), count: image.width * image.height * 4))
    }
}
