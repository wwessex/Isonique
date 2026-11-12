import CoreGraphics
import Foundation

public enum DefinitionRules {
    public static let strengthRange = 0.0...1.0
    /// Percentage of the image's shorter side.
    public static let radiusRange = 0.25...8.0
    public static let neutralRadius = 2.0
    public static let maximumLuminanceDelta = 0.12

    static func strength(_ value: Double) -> Double {
        value.isFinite ? min(strengthRange.upperBound, max(strengthRange.lowerBound, value)) : 0
    }

    static func radius(_ value: Double) -> Double {
        value.isFinite ? min(radiusRange.upperBound, max(radiusRange.lowerBound, value)) : neutralRadius
    }
}

public extension Renderer {
    /// Applies bounded luminance local contrast using a resolution-independent radius.
    static func applyDefinition(_ source: CGImage, strength: Double, radius: Double) throws -> CGImage {
        let strength = DefinitionRules.strength(strength)
        guard strength > 0 else { return source }
        return try applyingDefinition(source, radius: radius) { _, _ in strength }
    }

    /// Applies the same bounded Definition kernel through a source-space local mask.
    internal static func applyLocalDefinition(_ source: CGImage,
                                              mask: LocalAdjustmentMask?) throws -> CGImage {
        guard let mask, mask.isActive(.definition) else { return source }
        return try applyingDefinition(source, radius: DefinitionRules.neutralRadius) { x, y in
            mask.coverage(for: .definition, x: x, y: y,
                          imageWidth: source.width, imageHeight: source.height)
        }
    }

    private static func applyingDefinition(_ source: CGImage, radius: Double,
                                           strengthAt: (Int, Int) -> Double) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: source.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw LibraryError.unsupportedImage("definition") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4)
        let pixelRadius = max(1, Int((DefinitionRules.radius(radius) / 100 *
            Double(min(source.width, source.height))).rounded()))
        let blurred = try boxBlurredLuminance(pixels, width: source.width, height: source.height,
                                              radius: pixelRadius)

        for y in 0..<source.height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<source.width {
                let offset = (y * source.width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let red = Double(pixels[offset]) / (255 * alpha)
                let green = Double(pixels[offset + 1]) / (255 * alpha)
                let blue = Double(pixels[offset + 2]) / (255 * alpha)
                let strength = DefinitionRules.strength(strengthAt(x, y))
                guard strength > 0 else { continue }
                let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                let highPass = luminance - Double(blurred[y * source.width + x])
                let maximumDelta = DefinitionRules.maximumLuminanceDelta * strength
                let delta = min(maximumDelta, max(-maximumDelta, highPass * strength * 1.8))
                guard abs(delta) >= 0.5 / 255 else { continue }
                func encoded(_ channel: Double) -> UInt8 {
                    UInt8((min(1, max(0, channel + delta)) * alpha * 255).rounded())
                }
                pixels[offset] = encoded(red)
                pixels[offset + 1] = encoded(green)
                pixels[offset + 2] = encoded(blue)
            }
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("definition") }
        return result
    }

    private static func boxBlurredLuminance(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
                                             radius: Int) throws -> [Float] {
        let count = width * height
        var luminance = [Float](repeating: 0, count: count)
        var temporary = luminance
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let red = Double(pixels[offset]) / (255 * alpha)
                let green = Double(pixels[offset + 1]) / (255 * alpha)
                let blue = Double(pixels[offset + 2]) / (255 * alpha)
                luminance[y * width + x] = Float(0.2126 * red + 0.7152 * green + 0.0722 * blue)
            }
        }
        let diameter = Double(radius * 2 + 1)
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            var sum = 0.0
            for offset in -radius...radius {
                sum += Double(luminance[y * width + min(width - 1, max(0, offset))])
            }
            for x in 0..<width {
                temporary[y * width + x] = Float(sum / diameter)
                sum -= Double(luminance[y * width + min(width - 1, max(0, x - radius))])
                sum += Double(luminance[y * width + min(width - 1, max(0, x + radius + 1))])
            }
        }
        for x in 0..<width {
            var sum = 0.0
            for offset in -radius...radius {
                sum += Double(temporary[min(height - 1, max(0, offset)) * width + x])
            }
            for y in 0..<height {
                luminance[y * width + x] = Float(sum / diameter)
                sum -= Double(temporary[min(height - 1, max(0, y - radius)) * width + x])
                sum += Double(temporary[min(height - 1, max(0, y + radius + 1)) * width + x])
            }
        }
        return luminance
    }
}
