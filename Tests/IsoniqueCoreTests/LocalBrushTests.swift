import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class LocalBrushTests: XCTestCase {
    func testEdgeAwarenessProtectsContrastBoundaryAndSupportsEraseInvertAndOpacity() throws {
        let width = 100, height = 60
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let value: UInt8 = x < width / 2 ? 45 : 210
                let offset = (y * width + x) * 4
                pixels[offset] = value; pixels[offset + 1] = value; pixels[offset + 2] = value
            }
        }
        let edgeMap = pixels.withUnsafeBufferPointer {
            LocalBrushEdgeMap(pixels: $0.baseAddress!, width: width, height: height)
        }
        let point = BrushPoint(x: 0.4, y: 0.5)
        let protectedStroke = stroke(.dodge, points: [point], radius: 0.25,
                                     softness: 0, strength: 1, edgeAware: true)
        let ordinaryStroke = stroke(.dodge, points: [point], radius: 0.25,
                                    softness: 0, strength: 1)
        let protected = try XCTUnwrap(LocalExposureMask(strokes: [protectedStroke],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        let ordinary = try XCTUnwrap(LocalExposureMask(strokes: [ordinaryStroke],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        XCTAssertEqual(exposure(protected, 40, 30, width: width, height: height), 1.5, accuracy: 0.0001)
        XCTAssertEqual(exposure(protected, 52, 30, width: width, height: height), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(exposure(ordinary, 52, 30, width: width, height: height), 1.4)

        let erase = stroke(.dodge, points: [point], radius: 0.08, softness: 0,
                           strength: 1, erasing: true, edgeAware: true)
        let erased = try XCTUnwrap(LocalExposureMask(strokes: [protectedStroke, erase],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        XCTAssertEqual(exposure(erased, 40, 30, width: width, height: height), 0, accuracy: 0.0001)

        let settings: [LocalBrushAdjustment: LocalBrushMaskSettings] = [
            .dodge: LocalBrushMaskSettings(opacity: 0.4, inverted: false),
            .burn: LocalBrushMaskSettings(opacity: 1, inverted: true),
        ]
        let faded = try XCTUnwrap(LocalExposureMask(strokes: [protectedStroke], settings: settings,
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        XCTAssertEqual(exposure(faded, 40, 30, width: width, height: height), 0.6, accuracy: 0.0001)
        XCTAssertEqual(exposure(faded, 80, 30, width: width, height: height), 0, accuracy: 0.0001,
                       "An inverted setting must not activate an unpainted adjustment")
        let inverted = try XCTUnwrap(LocalExposureMask(strokes: [protectedStroke], settings: [
            .dodge: LocalBrushMaskSettings(opacity: 0.4, inverted: true),
        ], sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        XCTAssertEqual(exposure(inverted, 40, 30, width: width, height: height), 0, accuracy: 0.0001)
        XCTAssertEqual(exposure(inverted, 80, 30, width: width, height: height), 0.6, accuracy: 0.0001)
    }

    func testAdvancedBrushRecipesRequireSchema27AndLegacyStrokesRemainNeutral() throws {
        let legacyJSON = Data(#"{"adjustment":"Dodge","radius":0.1,"softness":0.5,"strength":0.8,"points":[{"x":0.2,"y":0.3}]}"#.utf8)
        let legacy = try JSONDecoder().decode(LocalBrushStroke.self, from: legacyJSON)
        XCTAssertFalse(legacy.edgeAware)
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8)).localBrushMaskSettings, [:])

        var library = Library()
        var photo = Photo(filename: "source.png", originalName: "source.png", projectID: nil,
                          width: 100, height: 60, camera: "", captureDate: "", sha256: "fixture")
        let advanced = stroke(.dodge, points: [BrushPoint(x: 0.2, y: 0.3)], radius: 0.1,
                              softness: 0.5, strength: 0.8, edgeAware: true)
        photo.adjustments.localBrushes = [advanced]
        photo.adjustments.localBrushMaskSettings[.dodge] = LocalBrushMaskSettings(opacity: 0.65, inverted: true)
        library.photos = [photo]
        XCTAssertThrowsError(try library.validateSchema())
        library.upgradeForAdvancedLocalBrushes()
        XCTAssertEqual(library.version, 27)
        XCTAssertNoThrow(try library.validateSchema())
        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded.photos[0].adjustments.localBrushes, [advanced])
        XCTAssertEqual(decoded.photos[0].adjustments.localBrushSettings(for: .dodge),
                       LocalBrushMaskSettings(opacity: 0.65, inverted: true))
    }

    func testMaskFalloffSamplingAndIndependentErasure() throws {
        let path = [BrushPoint(x: 0.25, y: 0.5), BrushPoint(x: 0.75, y: 0.5)]
        let dodge = stroke(.dodge, points: path, radius: 0.15, softness: 0.8, strength: 0.6)
        let sampled = stroke(.dodge, points: [path[0], BrushPoint(x: 0.5, y: 0.5), path[1]],
                             radius: 0.15, softness: 0.8, strength: 0.6)
        let original = try mask([dodge])
        let dense = try mask([sampled])
        XCTAssertEqual(exposure(original, 50, 50), 0.9, accuracy: 0.0001)
        XCTAssertEqual(exposure(original, 75, 50), 0.9, accuracy: 0.0001)
        XCTAssertEqual(exposure(original, 50, 70), 0)
        XCTAssertGreaterThan(exposure(original, 50, 59), 0)
        XCTAssertLessThan(exposure(original, 50, 59), 0.9)
        for y in 0..<100 {
            for x in 0..<100 {
                XCTAssertEqual(exposure(original, x, y), exposure(dense, x, y), accuracy: 0.00001)
            }
        }
        let burn = stroke(.burn, points: path, radius: 0.15, softness: 0.8, strength: 0.4)
        let erase = stroke(.dodge, points: [BrushPoint(x: 0.5, y: 0.5)], radius: 0.1,
                           softness: 0, strength: 1, erasing: true)
        let erased = try mask([dodge, burn, erase])
        XCTAssertEqual(exposure(erased, 50, 50), -0.6, accuracy: 0.0001)
        XCTAssertEqual(exposure(erased, 75, 50), 0.3, accuracy: 0.0001)
    }

    func testBrushPreviewAndPNGExportSharePixelsAndPreserveOriginal() throws {
        try withFixture { source, root in
            let repo = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
            var library = try repo.load()
            XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library))
            let digest = try LibraryRepository.digest(source)
            let dodge = stroke(.dodge, points: [BrushPoint(x: 0.25, y: 0.5)], radius: 0.15, softness: 0.5, strength: 1)
            let burn = stroke(.burn, points: [BrushPoint(x: 0.75, y: 0.5)], radius: 0.15, softness: 0.5, strength: 1)
            library.photos[0].adjustments.localBrushes = [dodge, burn]
            XCTAssertThrowsError(try repo.save(library))
            library.upgradeForBrushRecipes()
            XCTAssertEqual(library.version, 4)
            try repo.save(library)
            let photo = try XCTUnwrap(repo.load().photos.first)
            XCTAssertEqual(photo.adjustments.localBrushes, [dodge, burn])
            XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8)).localBrushes, [])
            XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.basic]).localBrushes, [])
            XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.localBrush]).localBrushes, [dodge, burn])
            XCTAssertEqual(AdjustmentPreset.vivid.applying(to: photo.adjustments).localBrushes, [dodge, burn])

            let preview = try Renderer.render(source, adjustments: photo.adjustments)
            let smallerPreview = try Renderer.render(source, adjustments: photo.adjustments, maxDimension: 100)
            let export = root.appendingPathComponent("Brushed.png")
            var options = ExportOptions()
            options.format = .png
            try Renderer.export(photo, repository: repo, to: export, options: options)
            let exported = try decode(export)
            XCTAssertEqual(try pixels(preview), try pixels(exported))
            let neutral = try Renderer.render(source, adjustments: Adjustments())
            XCTAssertGreaterThan(try red(preview, x: 0.25, y: 0.5), try red(neutral, x: 0.25, y: 0.5))
            XCTAssertLessThan(try red(preview, x: 0.75, y: 0.5), try red(neutral, x: 0.75, y: 0.5))
            XCTAssertEqual(try red(preview, x: 0.5, y: 0.5), try red(neutral, x: 0.5, y: 0.5))
            let resized = root.appendingPathComponent("Brushed-Small.png")
            options.maxDimension = 100
            try Renderer.export(photo, repository: repo, to: resized, options: options)
            let resizedExport = try decode(resized)
            XCTAssertEqual(smallerPreview.width, resizedExport.width)
            for point in [0.25, 0.32, 0.5, 0.68, 0.75] {
                XCTAssertEqual(Double(try red(smallerPreview, x: point, y: 0.5)),
                               Double(try red(resizedExport, x: point, y: 0.5)), accuracy: 2)
            }
            XCTAssertEqual(try LibraryRepository.digest(source), digest)
            XCTAssertEqual(try LibraryRepository.digest(repo.availableOriginalURL(photo)), digest)

            let backup = root.appendingPathComponent("Backup")
            let restored = root.appendingPathComponent("Restored")
            try LibraryBackup.create(from: repo, to: backup)
            try LibraryBackup.restore(from: backup, to: restored, excluding: repo.root)
            let (restoredRepository, restoredLibrary) = try LibraryBackup.openVerified(restored)
            let restoredPhoto = try XCTUnwrap(restoredLibrary.photos.first)
            XCTAssertEqual(restoredLibrary.version, 4)
            XCTAssertEqual(restoredPhoto.adjustments.localBrushes, [dodge, burn])
            XCTAssertEqual(try LibraryRepository.digest(restoredRepository.availableOriginalURL(restoredPhoto)), digest)
        }
    }

    func testBrushUsesOrientedCoordinatesForEXIFJPEG() throws {
        try withFixture { source, root in
            let oriented = root.appendingPathComponent("Oriented.jpg")
            let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(oriented as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(writer, try decode(source), [kCGImagePropertyOrientation: 6] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(writer))
            let (neutral, geometry) = try Renderer.renderWithGeometry(oriented, adjustments: Adjustments())
            XCTAssertEqual(geometry.sourceSize, CGSize(width: 120, height: 200))
            let target = geometry.sourcePoint(x: 0.72, y: 0.30)
            var settings = Adjustments()
            settings.localBrushes = [stroke(.burn, points: [target], radius: 0.1, softness: 0.5, strength: 1)]
            let painted = try Renderer.render(oriented, adjustments: settings, maxDimension: 100)
            XCTAssertLessThan(try red(painted, x: 0.72, y: 0.30), try red(neutral, x: 0.72, y: 0.30) - 20)
            XCTAssertEqual(try red(painted, x: 0.30, y: 0.72), try red(neutral, x: 0.30, y: 0.72))
        }
    }

    func testBrushCoordinatesFollowCropRotationFlipStraightenAndLens() throws {
        try withFixture { source, root in
            var settings = Adjustments()
            settings.quarterTurns = 1
            settings.flipHorizontal = true
            settings.flipVertical = true
            settings.straighten = 12
            settings.lensDistortion = 0.4
            settings.crop = PhotoCrop(x: 0.1, y: 0.15, width: 0.7, height: 0.8)
            let (neutral, geometry) = try Renderer.renderWithGeometry(source, adjustments: settings)
            let target = (x: 0.24, y: 0.68)
            let point = geometry.sourcePoint(x: target.x, y: target.y)
            settings.localBrushes = [stroke(.dodge, points: [point], radius: 0.08, softness: 0.3, strength: 1)]
            let painted = try Renderer.render(source, adjustments: settings)
            XCTAssertGreaterThan(try red(painted, x: target.x, y: target.y), try red(neutral, x: target.x, y: target.y) + 25)
            XCTAssertEqual(try red(painted, x: 0.84, y: 0.16), try red(neutral, x: 0.84, y: 0.16))
            let repo = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
            var library = try repo.load()
            XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library))
            library.photos[0].adjustments = settings
            var options = ExportOptions()
            options.format = .png
            let output = root.appendingPathComponent("Geometry.png")
            try Renderer.export(library.photos[0], repository: repo, to: output, options: options)
            XCTAssertEqual(try pixels(decode(output)), try pixels(painted))
            var uncropped = Adjustments()
            uncropped.localBrushes = settings.localBrushes
            let rendered = try Renderer.render(source, adjustments: uncropped)
            XCTAssertGreaterThan(try red(rendered, x: point.x, y: point.y), 140)
            XCTAssertEqual(try red(rendered, x: 0.03, y: 0.03), 105)
        }
    }

    private func stroke(_ adjustment: LocalBrushAdjustment, points: [BrushPoint], radius: Double,
                        softness: Double, strength: Double, erasing: Bool = false,
                        edgeAware: Bool = false) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: adjustment, erasing: erasing, radius: radius,
                         softness: softness, strength: strength, edgeAware: edgeAware, points: points)
    }

    private func mask(_ strokes: [LocalBrushStroke]) throws -> LocalExposureMask {
        try XCTUnwrap(LocalExposureMask(strokes: strokes, sourceWidth: 100, sourceHeight: 100))
    }

    private func exposure(_ mask: LocalExposureMask, _ x: Int, _ y: Int) -> Double {
        mask.exposure(x: x, y: y, imageWidth: 100, imageHeight: 100)
    }

    private func exposure(_ mask: LocalExposureMask, _ x: Int, _ y: Int,
                          width: Int, height: Int) -> Double {
        mask.exposure(x: x, y: y, imageWidth: width, imageHeight: height)
    }

    private func withFixture(_ body: (URL, URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueBrush-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Fixture.png")
        let context = try bitmap(width: 200, height: 120)
        let gray = 105.0 / 255
        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 120))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(source as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        try body(source, root)
    }

    private func bitmap(width: Int, height: Int) throws -> CGContext {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        return try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space, bitmapInfo: info))
    }

    private func decode(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let context = try bitmap(width: image.width, height: image.height)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return try Data(bytes: XCTUnwrap(context.data), count: image.width * image.height * 4)
    }

    private func red(_ image: CGImage, x: Double, y: Double) throws -> Int {
        let index = (Int(y * Double(image.height)) * image.width + Int(x * Double(image.width))) * 4
        return Int(try pixels(image)[index])
    }
}
