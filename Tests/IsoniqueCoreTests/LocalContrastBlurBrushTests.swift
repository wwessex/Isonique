import CoreGraphics
import XCTest
@testable import IsoniqueCore

final class LocalContrastBlurBrushTests: XCTestCase {
    func testFlatFieldsNeutralSettingsAndMaximumContrastAndBlur() throws {
        let flat = try image(width: 96, height: 64) { _, _ in 128 }
        let strokes = [stroke(.contrast, x: 0.5), stroke(.blur, x: 0.5)]
        let neutral = try XCTUnwrap(LocalAdjustmentMask(strokes: strokes, settings: [
            .contrast: LocalBrushMaskSettings(opacity: 0),
            .blur: LocalBrushMaskSettings(opacity: 0),
        ], sourceWidth: flat.width, sourceHeight: flat.height))
        let neutralResult = try Renderer.applyLocalBlur(
            Renderer.applyLocalContrast(flat, mask: neutral), mask: neutral)
        XCTAssertEqual(try pixels(neutralResult), try pixels(flat))

        let maximum = try XCTUnwrap(LocalAdjustmentMask(strokes: strokes,
            sourceWidth: flat.width, sourceHeight: flat.height))
        let contrastedFlat = try pixels(Renderer.applyLocalContrast(flat, mask: maximum))
        XCTAssertEqual(Set(stride(from: 0, to: contrastedFlat.count, by: 4).map { contrastedFlat[$0] }).count,
                       1, "Contrast must not create texture in a flat field")
        XCTAssertEqual(try pixels(Renderer.applyLocalBlur(flat, mask: maximum)), try pixels(flat))

        let tonalEdge = try image(width: 96, height: 64) { x, _ in x < 48 ? 90 : 166 }
        let contrasted = try pixels(Renderer.applyLocalContrast(tonalEdge, mask: maximum))
        let source = try pixels(tonalEdge)
        XCTAssertLessThan(red(contrasted, x: 40, y: 32, width: 96), red(source, x: 40, y: 32, width: 96))
        XCTAssertGreaterThan(red(contrasted, x: 56, y: 32, width: 96), red(source, x: 56, y: 32, width: 96))

        let texture = try image(width: 96, height: 64) { x, y in
            UInt8(128 + ((x + y).isMultiple(of: 2) ? -16 : 16))
        }
        let blurred = try Renderer.applyLocalBlur(texture, mask: maximum)
        XCTAssertLessThan(try adjacentContrast(blurred, x: 48, y: 32),
                          try adjacentContrast(texture, x: 48, y: 32))
    }

    func testEdgeAwareIndependentOverlappingEraseInvertAndOpacityMasks() throws {
        let width = 120, height = 64
        let source = try image(width: width, height: height) { x, y in
            let base = x < width / 2 ? 82 : 178
            return UInt8(base + ((x + y).isMultiple(of: 2) ? -8 : 8))
        }
        let sourcePixels = try pixels(source)
        let edgeMap = sourcePixels.withUnsafeBufferPointer {
            LocalBrushEdgeMap(pixels: $0.baseAddress!, width: width, height: height)
        }
        let contrast = stroke(.contrast, x: 0.4, edgeAware: true)
        let blur = stroke(.blur, x: 0.6, edgeAware: true)
        let erase = LocalBrushStroke(adjustment: .contrast, erasing: true, radius: 0.06,
            softness: 0, strength: 1, edgeAware: true,
            points: [BrushPoint(x: 0.35, y: 0.5)])
        let mask = try XCTUnwrap(LocalAdjustmentMask(strokes: [contrast, blur, erase], settings: [
            .contrast: LocalBrushMaskSettings(opacity: 0.5),
            .blur: LocalBrushMaskSettings(opacity: 0.25, inverted: true),
        ], sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))

        XCTAssertEqual(coverage(mask, .contrast, x: 42), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(coverage(mask, .contrast, x: 52), 0.49)
        XCTAssertEqual(coverage(mask, .contrast, x: 64), 0, accuracy: 0.0001)
        XCTAssertEqual(coverage(mask, .blur, x: 72), 0, accuracy: 0.0001)
        XCTAssertEqual(coverage(mask, .blur, x: 30), 0.25, accuracy: 0.0001)

        let protectedContrast = try XCTUnwrap(LocalAdjustmentMask(strokes: [contrast],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        let protectedBlur = try XCTUnwrap(LocalAdjustmentMask(strokes: [
            stroke(.blur, x: 0.4, edgeAware: true),
        ], sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        let contrasted = try pixels(Renderer.applyLocalContrast(source, mask: protectedContrast))
        let blurred = try pixels(Renderer.applyLocalBlur(source, mask: protectedBlur))
        let brightBoundary = (32 * width + 64) * 4
        XCTAssertEqual(contrasted[brightBoundary], sourcePixels[brightBoundary])
        XCTAssertEqual(blurred[brightBoundary], sourcePixels[brightBoundary])

        let overlapping = try XCTUnwrap(LocalAdjustmentMask(strokes: [
            stroke(.contrast, x: 0.5), stroke(.blur, x: 0.5),
        ], sourceWidth: width, sourceHeight: height))
        let onlyContrast = try Renderer.applyLocalContrast(source, mask: overlapping)
        let onlyBlur = try Renderer.applyLocalBlur(source, mask: overlapping)
        let composed = try Renderer.applyLocalBlur(onlyContrast, mask: overlapping)
        XCTAssertNotEqual(try pixels(composed), try pixels(onlyContrast))
        XCTAssertNotEqual(try pixels(composed), try pixels(onlyBlur))
    }

    func testLocalContrastBlurRecipeUsesFormat30AndRoundTrips() throws {
        var library = Library()
        var photo = Photo(filename: "source.png", originalName: "source.png", projectID: nil,
                          width: 120, height: 64, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.localBrushes = [stroke(.contrast, x: 0.3), stroke(.blur, x: 0.7)]
        photo.adjustments.localBrushMaskSettings[.blur] =
            LocalBrushMaskSettings(opacity: 0.6, inverted: true)
        library.photos = [photo]
        XCTAssertThrowsError(try library.validateSchema())
        library.upgradeForLocalContrastBlur()
        XCTAssertEqual(library.version, 30)
        XCTAssertNoThrow(try library.validateSchema())

        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded.photos[0].adjustments, photo.adjustments)
        XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.localBrush]).localBrushes,
                       photo.adjustments.localBrushes)
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

    private func image(width: Int, height: Int, value: (Int, Int) -> UInt8) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4, channel = value(x, y)
                bytes[offset] = channel; bytes[offset + 1] = channel; bytes[offset + 2] = channel
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

    private func red(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> Int {
        Int(pixels[(y * width + x) * 4])
    }

    private func adjacentContrast(_ image: CGImage, x: Int, y: Int) throws -> Int {
        let values = try pixels(image)
        return abs(red(values, x: x, y: y, width: image.width) -
                   red(values, x: x + 1, y: y, width: image.width))
    }
}
