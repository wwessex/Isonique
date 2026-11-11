import CoreGraphics

public enum BlackAndWhiteRules {
    public static let neutralRed = 0.2126
    public static let neutralGreen = 0.7152
    public static let neutralBlue = 0.0722
    public static let neutralTintHue = 30.0
    public static let contributionRange = 0.0...2.0

    static func contribution(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(contributionRange.upperBound, max(contributionRange.lowerBound, value))
    }
}

public extension Renderer {
    /// Shared sRGB channel mixer for full-resolution previews and edited exports.
    static func applyBlackAndWhite(_ source: CGImage, enabled: Bool,
                                   red: Double, green: Double, blue: Double,
                                   tintHue: Double, tintStrength: Double) throws -> CGImage {
        guard enabled else { return source }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: source.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw LibraryError.unsupportedImage("black and white") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4)
        let redWeight = BlackAndWhiteRules.contribution(red)
        let greenWeight = BlackAndWhiteRules.contribution(green)
        let blueWeight = BlackAndWhiteRules.contribution(blue)
        let strength = tintStrength.isFinite ? min(1, max(0, tintStrength)) : 0
        for y in 0..<source.height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<source.width {
                let offset = (y * source.width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let red = Double(pixels[offset]) / (255 * alpha)
                let green = Double(pixels[offset + 1]) / (255 * alpha)
                let blue = Double(pixels[offset + 2]) / (255 * alpha)
                let gray = min(1, max(0, red * redWeight + green * greenWeight + blue * blueWeight))
                let output = strength == 0
                    ? (red: gray, green: gray, blue: gray)
                    : TargetedColorTools.rgb(hue: tintHue, saturation: strength, luminance: gray)
                pixels[offset] = UInt8((min(1, max(0, output.red)) * alpha * 255).rounded())
                pixels[offset + 1] = UInt8((min(1, max(0, output.green)) * alpha * 255).rounded())
                pixels[offset + 2] = UInt8((min(1, max(0, output.blue)) * alpha * 255).rounded())
            }
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("black and white") }
        return result
    }
}
