import CoreGraphics
import Foundation

public enum WhiteBalanceRules {
    public static let minimumKelvin = 2_000.0
    public static let neutralKelvin = 6_500.0
    public static let maximumKelvin = 12_000.0
    static let maximumTemperatureComponent = 0.24

    public static func clamp(kelvin: Double) -> Double {
        guard kelvin.isFinite else { return neutralKelvin }
        return min(maximumKelvin, max(minimumKelvin, kelvin))
    }

    /// Converts Kelvin to the red/blue balance used by the shared sRGB renderer.
    /// Reciprocal temperature gives useful precision at the warm end of the range.
    static func temperatureComponent(for kelvin: Double) -> Double {
        let value = clamp(kelvin: kelvin)
        let neutral = 1_000_000 / neutralKelvin
        let current = 1_000_000 / value
        if value < neutralKelvin {
            let warmest = 1_000_000 / minimumKelvin
            return (neutral - current) / (warmest - neutral) * maximumTemperatureComponent
        }
        let coolest = 1_000_000 / maximumKelvin
        return (neutral - current) / (neutral - coolest) * maximumTemperatureComponent
    }

    static func kelvin(forTemperatureComponent component: Double) -> Double {
        let value = min(maximumTemperatureComponent, max(-maximumTemperatureComponent,
                                                          component.isFinite ? component : 0))
        let neutral = 1_000_000 / neutralKelvin
        let mired: Double
        if value < 0 {
            let warmest = 1_000_000 / minimumKelvin
            mired = neutral - value / maximumTemperatureComponent * (warmest - neutral)
        } else {
            let coolest = 1_000_000 / maximumKelvin
            mired = neutral - value / maximumTemperatureComponent * (neutral - coolest)
        }
        return clamp(kelvin: 1_000_000 / mired)
    }
}

public struct WhiteBalanceSample: Equatable {
    public let red: Int
    public let green: Int
    public let blue: Int
    public let kelvin: Double
    public let tint: Double
}

public extension Adjustments {
    var displayedTemperatureKelvin: Double {
        if temperatureKelvin != WhiteBalanceRules.neutralKelvin || warmth == 0 {
            return WhiteBalanceRules.clamp(kelvin: temperatureKelvin)
        }
        return WhiteBalanceRules.kelvin(forTemperatureComponent:
            min(WhiteBalanceRules.maximumTemperatureComponent,
                max(-WhiteBalanceRules.maximumTemperatureComponent, warmth * 0.15)))
    }
}

public extension Renderer {
    /// Samples the opaque, unclipped source pixel under a full-size Viewer point before white balance.
    static func sampleWhiteBalance(_ url: URL, adjustments: Adjustments,
                                   viewerPoint: CGPoint) throws -> WhiteBalanceSample? {
        guard (0...1).contains(viewerPoint.x), (0...1).contains(viewerPoint.y) else { return nil }
        var neutral = adjustments
        neutral.warmth = 0
        neutral.temperatureKelvin = WhiteBalanceRules.neutralKelvin
        neutral.tint = 0
        let (image, geometry) = try renderToneInput(url, adjustments: neutral, maxDimension: nil)
        try Task.checkCancellation()
        let source = geometry.sourcePoint(x: viewerPoint.x, y: viewerPoint.y)
        let x = min(image.width - 1, max(0, Int(source.x * Double(image.width))))
        let y = min(image.height - 1, max(0, Int(source.y * Double(image.height))))
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                      bytesPerRow: 4, space: space, bitmapInfo: info),
              let data = context.data else { return nil }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let bytes = data.assumingMemoryBound(to: UInt8.self)
        let alpha = Int(bytes[3])
        guard alpha == 255 else { return nil }
        let channels = (0..<3).map { Int(bytes[$0]) }
        guard channels.allSatisfy({ $0 > 1 && $0 < 254 }) else { return nil }

        let red = Double(channels[0]), green = Double(channels[1]), blue = Double(channels[2])
        let first = 0.5 * red + green
        let second = 0.5 * blue + green
        let determinant = red * second + blue * first
        guard determinant > 0 else { return nil }
        let redDifference = green - red
        let blueDifference = green - blue
        let temperature = (redDifference * second - first * blueDifference) / determinant
        let tintComponent = (red * blueDifference + blue * redDifference) / determinant
        let kelvin = WhiteBalanceRules.kelvin(forTemperatureComponent: temperature)
        let tint = min(1, max(-1, tintComponent / 0.15))
        return WhiteBalanceSample(red: channels[0], green: channels[1], blue: channels[2],
                                  kelvin: kelvin, tint: tint)
    }
}
