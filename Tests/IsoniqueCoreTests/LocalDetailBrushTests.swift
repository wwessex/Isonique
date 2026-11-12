import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class LocalDetailBrushTests: XCTestCase {
    func testFlatFieldsStayNeutralAndIndependentMasksActOnFineDetail() throws {
        let flat = try image(width: 96, height: 64) { _, _ in 128 }
        let full = try XCTUnwrap(LocalAdjustmentMask(strokes: [
            stroke(.sharpening, x: 0.5, radius: 0.25),
            stroke(.noiseReduction, x: 0.5, radius: 0.25),
        ], sourceWidth: flat.width, sourceHeight: flat.height))
        let flatReduced = try Renderer.applyLocalLuminanceNoiseReduction(flat, mask: full)
        let flatSharpened = try Renderer.applyLocalSharpening(flat, mask: full)
        XCTAssertEqual(try pixels(flatReduced), try pixels(flat))
        XCTAssertEqual(try pixels(flatSharpened), try pixels(flat))

        let texture = try image(width: 120, height: 64) { x, y in
            UInt8(128 + ((x + y).isMultiple(of: 2) ? -12 : 12))
        }
        let sharpening = try XCTUnwrap(LocalAdjustmentMask(strokes: [
            stroke(.sharpening, x: 0.25, radius: 0.22),
        ], sourceWidth: texture.width, sourceHeight: texture.height))
        let noiseReduction = try XCTUnwrap(LocalAdjustmentMask(strokes: [
            stroke(.noiseReduction, x: 0.75, radius: 0.22),
        ], sourceWidth: texture.width, sourceHeight: texture.height))
        let sharpened = try Renderer.applyLocalSharpening(texture, mask: sharpening)
        let reduced = try Renderer.applyLocalLuminanceNoiseReduction(texture, mask: noiseReduction)
        XCTAssertGreaterThan(try adjacentContrast(sharpened, x: 30, y: 32),
                             try adjacentContrast(texture, x: 30, y: 32))
        XCTAssertEqual(try adjacentContrast(sharpened, x: 90, y: 32),
                       try adjacentContrast(texture, x: 90, y: 32), accuracy: 0.01)
        XCTAssertLessThan(try adjacentContrast(reduced, x: 90, y: 32),
                          try adjacentContrast(texture, x: 90, y: 32))
        XCTAssertEqual(try adjacentContrast(reduced, x: 30, y: 32),
                       try adjacentContrast(texture, x: 30, y: 32), accuracy: 0.01)
    }

    func testOverlappingMasksComposeAndEdgeAwareEraseInvertOpacityStayIndependent() throws {
        let width = 120, height = 64
        let source = try image(width: width, height: height) { x, y in
            let base = x < width / 2 ? 80 : 180
            return UInt8(base + ((x + y).isMultiple(of: 2) ? -10 : 10))
        }
        let sourcePixels = try pixels(source)
        let edgeMap = sourcePixels.withUnsafeBufferPointer {
            LocalBrushEdgeMap(pixels: $0.baseAddress!, width: width, height: height)
        }
        let sharpen = stroke(.sharpening, x: 0.4, radius: 0.25, edgeAware: true)
        let reduce = stroke(.noiseReduction, x: 0.6, radius: 0.25, edgeAware: true)
        let protectedNoise = stroke(.noiseReduction, x: 0.4, radius: 0.25, edgeAware: true)
        let erase = LocalBrushStroke(adjustment: .sharpening, erasing: true, radius: 0.06,
            softness: 0, strength: 1, edgeAware: true,
            points: [BrushPoint(x: 0.35, y: 0.5)])
        let mask = try XCTUnwrap(LocalAdjustmentMask(strokes: [sharpen, reduce, erase], settings: [
            .sharpening: LocalBrushMaskSettings(opacity: 0.5),
            .noiseReduction: LocalBrushMaskSettings(opacity: 0.25, inverted: true),
        ], sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))

        XCTAssertEqual(coverage(mask, .sharpening, x: 42, y: 32), 0, accuracy: 0.0001)
        XCTAssertGreaterThan(coverage(mask, .sharpening, x: 52, y: 32), 0.49)
        XCTAssertEqual(coverage(mask, .sharpening, x: 64, y: 32), 0, accuracy: 0.0001,
                       "Edge-aware sharpening must not cross the contrast boundary")
        XCTAssertEqual(coverage(mask, .noiseReduction, x: 72, y: 32), 0, accuracy: 0.0001)
        XCTAssertEqual(coverage(mask, .noiseReduction, x: 30, y: 32), 0.25, accuracy: 0.0001)

        let sharpeningMask = try XCTUnwrap(LocalAdjustmentMask(strokes: [sharpen],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        let noiseMask = try XCTUnwrap(LocalAdjustmentMask(strokes: [protectedNoise],
            sourceWidth: width, sourceHeight: height, edgeMap: edgeMap))
        let protectedSharpening = try pixels(Renderer.applyLocalSharpening(source, mask: sharpeningMask))
        let protectedReduction = try pixels(Renderer.applyLocalLuminanceNoiseReduction(source, mask: noiseMask))
        let boundaryOffset = (32 * width + 64) * 4
        XCTAssertEqual(protectedSharpening[boundaryOffset], sourcePixels[boundaryOffset])
        XCTAssertEqual(protectedReduction[boundaryOffset], sourcePixels[boundaryOffset])
        let first = (32 * width + 52) * 4, second = (32 * width + 53) * 4
        let reducedContrast = abs(Int(protectedReduction[first]) - Int(protectedReduction[second]))
        let sourceContrast = abs(Int(sourcePixels[first]) - Int(sourcePixels[second]))
        XCTAssertLessThan(reducedContrast, sourceContrast)

        let overlapping = try XCTUnwrap(LocalAdjustmentMask(strokes: [
            stroke(.sharpening, x: 0.5, radius: 0.25),
            stroke(.noiseReduction, x: 0.5, radius: 0.25),
        ], sourceWidth: width, sourceHeight: height))
        let reduced = try Renderer.applyLocalLuminanceNoiseReduction(source, mask: overlapping)
        let composed = try Renderer.applyLocalSharpening(reduced, mask: overlapping)
        let onlyReduced = try Renderer.applyLocalLuminanceNoiseReduction(source, mask: overlapping)
        let onlySharpened = try Renderer.applyLocalSharpening(source, mask: overlapping)
        XCTAssertNotEqual(try pixels(composed), try pixels(onlyReduced))
        XCTAssertNotEqual(try pixels(composed), try pixels(onlySharpened))
    }

    func testLocalDetailBrushRecipeUsesFormat29AndRoundTrips() throws {
        var library = Library()
        var photo = Photo(filename: "source.png", originalName: "source.png", projectID: nil,
                          width: 120, height: 64, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.localBrushes = [
            stroke(.sharpening, x: 0.3, radius: 0.2),
            stroke(.noiseReduction, x: 0.7, radius: 0.2),
        ]
        photo.adjustments.localBrushMaskSettings[.noiseReduction] =
            LocalBrushMaskSettings(opacity: 0.6, inverted: true)
        library.photos = [photo]
        XCTAssertThrowsError(try library.validateSchema())
        library.upgradeForLocalDetailBrushes()
        XCTAssertEqual(library.version, 29)
        XCTAssertNoThrow(try library.validateSchema())

        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded.photos[0].adjustments, photo.adjustments)
        XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.localBrush]).localBrushes,
                       photo.adjustments.localBrushes)
        XCTAssertEqual(photo.adjustments.stamping(onto: Adjustments(), groups: [.detail]).localBrushes, [])
    }

    private func stroke(_ adjustment: LocalBrushAdjustment, x: Double, radius: Double,
                        edgeAware: Bool = false) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: adjustment, radius: radius, softness: 0,
                         strength: 1, edgeAware: edgeAware,
                         points: [BrushPoint(x: x, y: 0.5)])
    }

    private func coverage(_ mask: LocalAdjustmentMask, _ adjustment: LocalBrushAdjustment,
                          x: Int, y: Int) -> Double {
        mask.coverage(for: adjustment, x: x, y: y, imageWidth: 120, imageHeight: 64)
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

    private func adjacentContrast(_ image: CGImage, x: Int, y: Int) throws -> Double {
        let values = try pixels(image)
        let left = Double(values[(y * image.width + x) * 4])
        let right = Double(values[(y * image.width + x + 1) * 4])
        return abs(left - right)
    }
}
