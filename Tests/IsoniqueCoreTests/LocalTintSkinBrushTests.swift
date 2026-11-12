import CoreGraphics
import XCTest
@testable import IsoniqueCore

final class LocalTintSkinBrushTests: XCTestCase {
    func testTintNeutralMaximumHueAndFlatField() throws {
        let source = try image(width: 96, height: 64) { _, _ in (128, 128, 128) }
        let mask = try XCTUnwrap(LocalAdjustmentMask(strokes: [stroke(.tint, x: 0.5)],
            sourceWidth: source.width, sourceHeight: source.height))
        XCTAssertEqual(try pixels(Renderer.applyLocalTint(source,
            settings: LocalTintSettings(hue: 0, saturation: 0), mask: mask)), try pixels(source))

        let red = try pixels(Renderer.applyLocalTint(source,
            settings: LocalTintSettings(hue: 0, saturation: 1), mask: mask))
        let redPixel = pixel(red, x: 48, y: 32, width: 96)
        XCTAssertGreaterThan(redPixel.red, redPixel.green + 200)
        XCTAssertGreaterThan(redPixel.red, redPixel.blue + 200)

        let wrappedGreen = try pixels(Renderer.applyLocalTint(source,
            settings: LocalTintSettings(hue: 480, saturation: 1), mask: mask))
        let greenPixel = pixel(wrappedGreen, x: 48, y: 32, width: 96)
        XCTAssertGreaterThan(greenPixel.green, greenPixel.red + 200)
        XCTAssertGreaterThan(greenPixel.green, greenPixel.blue + 200)
        XCTAssertEqual(pixel(red, x: 48, y: 32, width: 96),
                       pixel(red, x: 49, y: 32, width: 96),
                       "Tint must not create texture within a flat painted field")
    }

    func testSkinSmoothingSelectsSkinAndPreservesDetailAtMaximum() throws {
        let source = try skinAndNonSkinTexture()
        let mask = try XCTUnwrap(LocalAdjustmentMask(strokes: [stroke(.skinSmoothing, x: 0.5)],
            sourceWidth: source.width, sourceHeight: source.height))
        let neutral = try Renderer.applyLocalSkinSmoothing(source,
            settings: LocalSkinSmoothingSettings(amount: 0, detailPreservation: 0), mask: mask)
        XCTAssertEqual(try pixels(neutral), try pixels(source))

        let smoothed = try Renderer.applyLocalSkinSmoothing(source,
            settings: LocalSkinSmoothingSettings(amount: 1, detailPreservation: 0), mask: mask)
        let preserved = try Renderer.applyLocalSkinSmoothing(source,
            settings: LocalSkinSmoothingSettings(amount: 1, detailPreservation: 1), mask: mask)
        XCTAssertLessThan(try adjacentLuminanceContrast(smoothed, x: 48, y: 32),
                          try adjacentLuminanceContrast(source, x: 48, y: 32))
        XCTAssertGreaterThan(try adjacentLuminanceContrast(preserved, x: 48, y: 32),
                             try adjacentLuminanceContrast(smoothed, x: 48, y: 32))

        let sourcePixels = try pixels(source), outputPixels = try pixels(smoothed)
        XCTAssertEqual(pixel(outputPixels, x: 72, y: 32, width: 120),
                       pixel(sourcePixels, x: 72, y: 32, width: 120),
                       "Non-skin colour must remain neutral even inside the mask")
    }

    func testEdgeAwareIndependentOverlappingEraseInvertAndOpacityMasks() throws {
        let width = 120, height = 64
        let source = try image(width: width, height: height) { x, y in
            let texture = (x + y).isMultiple(of: 2) ? -4 : 4
            return x < width / 2
                ? (UInt8(132 + texture), UInt8(82 + texture), UInt8(60 + texture))
                : (UInt8(225 + texture), UInt8(180 + texture), UInt8(150 + texture))
        }
        let sourcePixels = try pixels(source)
        let edgeMap = sourcePixels.withUnsafeBufferPointer {
            LocalBrushEdgeMap(pixels: $0.baseAddress!, width: width, height: height)
        }
        let tint = stroke(.tint, x: 0.4, edgeAware: true)
        let skin = stroke(.skinSmoothing, x: 0.4, edgeAware: true)
        let erase = LocalBrushStroke(adjustment: .tint, erasing: true, radius: 0.06,
            softness: 0, strength: 1, edgeAware: true,
            points: [BrushPoint(x: 0.35, y: 0.5)])
        let mask = try XCTUnwrap(LocalAdjustmentMask(strokes: [tint, skin, erase], settings: [
            .tint: LocalBrushMaskSettings(opacity: 0.5),
            .skinSmoothing: LocalBrushMaskSettings(opacity: 0.25, inverted: true),
        ], sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        XCTAssertEqual(coverage(mask, .tint, x: 42), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(coverage(mask, .tint, x: 52), 0.49)
        XCTAssertEqual(coverage(mask, .tint, x: 64), 0, accuracy: 0.0001)
        XCTAssertEqual(coverage(mask, .skinSmoothing, x: 48), 0, accuracy: 0.0001)
        XCTAssertEqual(coverage(mask, .skinSmoothing, x: 90), 0.25, accuracy: 0.0001)

        let protectedTint = try XCTUnwrap(LocalAdjustmentMask(strokes: [tint],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        let protectedSkin = try XCTUnwrap(LocalAdjustmentMask(strokes: [skin],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        let tinted = try pixels(Renderer.applyLocalTint(source,
            settings: LocalTintSettings(hue: 210, saturation: 1), mask: protectedTint))
        let smoothed = try pixels(Renderer.applyLocalSkinSmoothing(source,
            settings: LocalSkinSmoothingSettings(amount: 1, detailPreservation: 0), mask: protectedSkin))
        XCTAssertEqual(pixel(tinted, x: 64, y: 32, width: width),
                       pixel(sourcePixels, x: 64, y: 32, width: width))
        XCTAssertEqual(pixel(smoothed, x: 64, y: 32, width: width),
                       pixel(sourcePixels, x: 64, y: 32, width: width))

        let texture = try skinAndNonSkinTexture()
        let overlap = try XCTUnwrap(LocalAdjustmentMask(strokes: [
            stroke(.tint, x: 0.45), stroke(.skinSmoothing, x: 0.45),
        ], sourceWidth: texture.width, sourceHeight: texture.height))
        let onlyTint = try Renderer.applyLocalTint(texture,
            settings: LocalTintSettings(hue: 340, saturation: 0.8), mask: overlap)
        let onlySkin = try Renderer.applyLocalSkinSmoothing(texture,
            settings: LocalSkinSmoothingSettings(amount: 1, detailPreservation: 0), mask: overlap)
        let composed = try Renderer.applyLocalTint(onlySkin,
            settings: LocalTintSettings(hue: 340, saturation: 0.8), mask: overlap)
        XCTAssertNotEqual(try pixels(composed), try pixels(onlyTint))
        XCTAssertNotEqual(try pixels(composed), try pixels(onlySkin))
    }

    func testTintSkinRecipeUsesFormat31AndRoundTripsSettings() throws {
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8)).localTintSettings,
                       LocalTintSettings())
        XCTAssertEqual(try JSONDecoder().decode(Adjustments.self, from: Data("{}".utf8))
            .localSkinSmoothingSettings, LocalSkinSmoothingSettings())
        var library = Library()
        var photo = Photo(filename: "source.png", originalName: "source.png", projectID: nil,
                          width: 120, height: 64, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.localBrushes = [stroke(.tint, x: 0.3), stroke(.skinSmoothing, x: 0.7)]
        photo.adjustments.localTintSettings = LocalTintSettings(hue: 215, saturation: 0.8)
        photo.adjustments.localSkinSmoothingSettings =
            LocalSkinSmoothingSettings(amount: 0.9, detailPreservation: 0.3)
        library.photos = [photo]
        XCTAssertThrowsError(try library.validateSchema())
        library.upgradeForLocalTintSkin()
        XCTAssertEqual(library.version, 31)
        XCTAssertNoThrow(try library.validateSchema())

        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded.photos[0].adjustments, photo.adjustments)
        let stamped = photo.adjustments.stamping(onto: Adjustments(), groups: [.localBrush])
        XCTAssertEqual(stamped.localTintSettings, photo.adjustments.localTintSettings)
        XCTAssertEqual(stamped.localSkinSmoothingSettings, photo.adjustments.localSkinSmoothingSettings)
        XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.detail]).localBrushes, [])
    }

    private func stroke(_ adjustment: LocalBrushAdjustment, x: Double,
                        edgeAware: Bool = false) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: adjustment, radius: 0.25, softness: 0,
                         strength: 1, edgeAware: edgeAware,
                         points: [BrushPoint(x: x, y: 0.5)])
    }

    private func coverage(_ mask: LocalAdjustmentMask, _ adjustment: LocalBrushAdjustment,
                          x: Int) -> Double {
        mask.coverage(for: adjustment, x: x, y: 32, imageWidth: 120, imageHeight: 64)
    }

    private func skinAndNonSkinTexture() throws -> CGImage {
        try image(width: 120, height: 64) { x, y in
            let delta = (x + y).isMultiple(of: 2) ? -10 : 10
            return x < 60
                ? (UInt8(190 + delta), UInt8(130 + delta), UInt8(100 + delta))
                : (UInt8(70 + delta), UInt8(160 + delta), UInt8(90 + delta))
        }
    }

    private func image(width: Int, height: Int,
                       value: (Int, Int) -> (UInt8, UInt8, UInt8)) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4, channels = value(x, y)
                bytes[offset] = channels.0; bytes[offset + 1] = channels.1; bytes[offset + 2] = channels.2
            }
        }
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let provider = try XCTUnwrap(CGDataProvider(data: Data(bytes) as CFData))
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8,
            bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var values = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &values, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return values
    }

    private struct RGB: Equatable {
        let red: Int
        let green: Int
        let blue: Int
    }

    private func pixel(_ values: [UInt8], x: Int, y: Int, width: Int) -> RGB {
        let offset = (y * width + x) * 4
        return RGB(red: Int(values[offset]), green: Int(values[offset + 1]),
                   blue: Int(values[offset + 2]))
    }

    private func adjacentLuminanceContrast(_ image: CGImage, x: Int, y: Int) throws -> Double {
        let values = try pixels(image)
        func luminance(_ pixel: RGB) -> Double {
            0.2126 * Double(pixel.red) + 0.7152 * Double(pixel.green) + 0.0722 * Double(pixel.blue)
        }
        return abs(luminance(pixel(values, x: x, y: y, width: image.width)) -
                   luminance(pixel(values, x: x + 1, y: y, width: image.width)))
    }
}
