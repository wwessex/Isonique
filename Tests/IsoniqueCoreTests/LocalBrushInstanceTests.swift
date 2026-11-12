import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class LocalBrushInstanceTests: XCTestCase {
    func testLegacyRecipeMigratesWithoutChangingPixelsAndUsesFormat32() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Legacy.png")
        try writeFixture(source)

        var legacy = Adjustments()
        legacy.localBrushes = [stroke(.tint, x: 0.34), stroke(.blur, x: 0.68)]
        legacy.localBrushMaskSettings[.tint] = LocalBrushMaskSettings(opacity: 0.7, inverted: false)
        legacy.localTintSettings = LocalTintSettings(hue: 18, saturation: 0.65)
        let before = try pixels(Renderer.render(source, adjustments: legacy))

        var migrated = legacy
        migrated.migrateLocalBrushInstances()
        XCTAssertTrue(migrated.localBrushes.isEmpty)
        XCTAssertTrue(migrated.localBrushMaskSettings.isEmpty)
        XCTAssertEqual(migrated.localBrushInstances.map(\.adjustment), [.blur, .tint],
                       "Legacy groups use the stable adjustment order")
        let tint = try XCTUnwrap(migrated.localBrushInstances.first { $0.adjustment == .tint })
        XCTAssertEqual(tint.name, "Tint")
        XCTAssertEqual(tint.maskSettings.opacity, 0.7)
        XCTAssertEqual(tint.tintSettings, legacy.localTintSettings)
        XCTAssertEqual(try pixels(Renderer.render(source, adjustments: migrated)), before)

        var photo = Photo(filename: "Legacy.png", originalName: "Legacy.png", projectID: nil,
                          width: 96, height: 64, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments = migrated
        var library = Library()
        library.version = 31
        library.photos = [photo]
        XCTAssertThrowsError(try library.validateSchema())
        library.upgradeForLocalBrushInstances()
        XCTAssertEqual(library.version, 32)
        XCTAssertNoThrow(try library.validateSchema())
        let reopened = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(reopened.photos[0].adjustments, migrated)
    }

    func testOrderEnableAndIndependentMasksAndParameters() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Order.png")
        try writeFixture(source, flat: true)
        let red = LocalBrushInstance(name: "Warm", adjustment: .tint,
            strokes: [stroke(.tint, x: 0.5, radius: 0.25)],
            tintSettings: LocalTintSettings(hue: 0, saturation: 0.65))
        let blue = LocalBrushInstance(name: "Cool", adjustment: .tint,
            strokes: [stroke(.tint, x: 0.5, radius: 0.25)],
            tintSettings: LocalTintSettings(hue: 240, saturation: 0.65))
        var recipe = Adjustments()
        recipe.localBrushInstances = [red, blue]
        let warmThenCool = try pixels(Renderer.render(source, adjustments: recipe))
        recipe.localBrushInstances = [blue, red]
        let coolThenWarm = try pixels(Renderer.render(source, adjustments: recipe))
        XCTAssertNotEqual(warmThenCool, coolThenWarm, "Same-type instance order must affect compositing")

        recipe.localBrushInstances = [red, blue]
        recipe.localBrushInstances[1].enabled = false
        var redOnly = Adjustments()
        redOnly.localBrushInstances = [red]
        XCTAssertEqual(try pixels(Renderer.render(source, adjustments: recipe)),
                       try pixels(Renderer.render(source, adjustments: redOnly)))

        var split = Adjustments()
        split.localBrushInstances = [
            LocalBrushInstance(name: "Left red", adjustment: .tint,
                strokes: [stroke(.tint, x: 0.25, radius: 0.12)],
                tintSettings: LocalTintSettings(hue: 0, saturation: 1)),
            LocalBrushInstance(name: "Right blue", adjustment: .tint,
                strokes: [stroke(.tint, x: 0.75, radius: 0.12)],
                tintSettings: LocalTintSettings(hue: 240, saturation: 1)),
        ]
        let rendered = try pixels(Renderer.render(source, adjustments: split))
        let left = pixel(rendered, x: 24, y: 32, width: 96)
        let right = pixel(rendered, x: 72, y: 32, width: 96)
        XCTAssertGreaterThan(left.0, left.2)
        XCTAssertGreaterThan(right.2, right.0)
    }

    func testLiftStampAndCustomPresetsCopyInstancesOnlyWhenSelected() throws {
        var source = Adjustments()
        source.localBrushInstances = [
            LocalBrushInstance(name: "Portrait tint", adjustment: .tint, enabled: false,
                strokes: [stroke(.tint, x: 0.4)], maskSettings: LocalBrushMaskSettings(opacity: 0.55),
                tintSettings: LocalTintSettings(hue: 28, saturation: 0.4)),
            LocalBrushInstance(name: "Fine skin", adjustment: .skinSmoothing,
                strokes: [stroke(.skinSmoothing, x: 0.6)],
                skinSmoothingSettings: LocalSkinSmoothingSettings(amount: 0.8, detailPreservation: 0.7)),
        ]
        var target = Adjustments()
        target.localBrushInstances = [LocalBrushInstance(name: "Existing", adjustment: .dodge)]

        let stamped = source.stamping(onto: target, groups: [.localBrush])
        XCTAssertEqual(stamped.localBrushInstances, source.localBrushInstances)
        XCTAssertEqual(source.stamping(onto: target, groups: [.detail]).localBrushInstances,
                       target.localBrushInstances)

        let spatialPreset = CustomAdjustmentPreset(name: "Portrait", adjustments: source,
                                                    groups: [.localBrush])
        XCTAssertEqual(spatialPreset.applying(to: target).localBrushInstances, source.localBrushInstances)
        XCTAssertEqual(try JSONDecoder().decode(CustomAdjustmentPreset.self,
            from: JSONEncoder().encode(spatialPreset)), spatialPreset)
        let safePreset = CustomAdjustmentPreset(name: "Safe", adjustments: source)
        XCTAssertEqual(safePreset.applying(to: target).localBrushInstances, target.localBrushInstances)
    }

    private func stroke(_ adjustment: LocalBrushAdjustment, x: Double,
                        radius: Double = 0.2) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: adjustment, radius: radius, softness: 0.2,
                         strength: 1, edgeAware: false, points: [BrushPoint(x: x, y: 0.5)])
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueBrushInstances-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return folder
    }

    private func writeFixture(_ url: URL, flat: Bool = false) throws {
        let width = 96, height = 64
        var values = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let variation = flat ? 0 : ((x + y).isMultiple(of: 2) ? -8 : 8)
                values[offset] = UInt8(128 + variation)
                values[offset + 1] = UInt8(128 + variation)
                values[offset + 2] = UInt8(128 + variation)
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

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &result, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return result
    }

    private func pixel(_ values: [UInt8], x: Int, y: Int, width: Int) -> (Int, Int, Int) {
        let offset = (y * width + x) * 4
        return (Int(values[offset]), Int(values[offset + 1]), Int(values[offset + 2]))
    }
}
