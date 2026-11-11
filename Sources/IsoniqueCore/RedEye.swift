import CoreGraphics
import Foundation

/// A non-destructive circular pupil correction in the EXIF-oriented source image.
public struct RedEyeCorrection: Codable, Equatable, Identifiable {
    public var id: UUID
    public var center: BrushPoint
    /// Radius as a fraction of the shorter side of the oriented source.
    public var radius: Double
    /// Additional darkening after removing red dominance.
    public var darkness: Double

    public init(id: UUID = UUID(), center: BrushPoint, radius: Double, darkness: Double) {
        self.id = id
        self.center = center
        self.radius = radius
        self.darkness = darkness
    }

    public var isValid: Bool {
        (0.0025...0.25).contains(radius) && (0...1).contains(darkness) &&
            [center.x, center.y, radius, darkness].allSatisfy(\.isFinite) &&
            (0...1).contains(center.x) && (0...1).contains(center.y)
    }
}

public extension Renderer {
    /// Corrects red-dominant pupil pixels without changing neutral or non-red pixels.
    static func applyRedEyeCorrections(_ source: CGImage, corrections: [RedEyeCorrection]) throws -> CGImage {
        let valid = corrections.filter(\.isValid)
        guard !valid.isEmpty else { return source }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: source.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw LibraryError.unsupportedImage("red-eye correction") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4)
        let shortEdge = Double(min(source.width, source.height))

        for correction in valid {
            try Task.checkCancellation()
            let radius = max(1, correction.radius * shortEdge)
            let center = CGPoint(x: correction.center.x * Double(source.width),
                                 y: correction.center.y * Double(source.height))
            let x0 = max(0, Int(floor(center.x - radius)))
            let x1 = min(source.width, Int(ceil(center.x + radius)))
            let y0 = max(0, Int(floor(center.y - radius)))
            let y1 = min(source.height, Int(ceil(center.y + radius)))
            guard x0 < x1, y0 < y1 else { continue }
            let featherStart = radius * 0.72
            let darkScale = 1 - correction.darkness * 0.85

            for y in y0..<y1 {
                if y.isMultiple(of: 32) { try Task.checkCancellation() }
                for x in x0..<x1 {
                    let distance = hypot(Double(x) + 0.5 - center.x, Double(y) + 0.5 - center.y)
                    guard distance <= radius else { continue }
                    let offset = (y * source.width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let red = Double(pixels[offset]) / (255 * alpha)
                    let green = Double(pixels[offset + 1]) / (255 * alpha)
                    let blue = Double(pixels[offset + 2]) / (255 * alpha)
                    let strongestOther = max(green, blue)
                    let excess = red - strongestOther
                    // Preserve skin, highlights and every neutral/non-red pixel exactly.
                    guard excess > 4.0 / 255, red > strongestOther * 1.15 else { continue }
                    let detection = min(1, excess / 0.25)
                    let feather: Double
                    if distance <= featherStart { feather = 1 }
                    else {
                        let amount = max(0, min(1, (radius - distance) / (radius - featherStart)))
                        feather = amount * amount * (3 - 2 * amount)
                    }
                    let amount = detection * feather
                    let neutral = (green + blue) * 0.5
                    let target = (red: neutral * darkScale, green: green * darkScale, blue: blue * darkScale)
                    let output = (
                        red: red + (target.red - red) * amount,
                        green: green + (target.green - green) * amount,
                        blue: blue + (target.blue - blue) * amount
                    )
                    pixels[offset] = UInt8((min(1, max(0, output.red)) * alpha * 255).rounded())
                    pixels[offset + 1] = UInt8((min(1, max(0, output.green)) * alpha * 255).rounded())
                    pixels[offset + 2] = UInt8((min(1, max(0, output.blue)) * alpha * 255).rounded())
                }
            }
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("red-eye correction") }
        return result
    }
}
