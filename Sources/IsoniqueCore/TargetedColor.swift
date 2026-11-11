import CoreGraphics
import Foundation

public struct TargetedColorAdjustment: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var centerHue: Double
    public var width: Double
    public var falloff: Double
    public var hueShift: Double
    public var saturation: Double
    public var luminance: Double

    public init(id: UUID = UUID(), name: String, centerHue: Double, width: Double = 40,
                falloff: Double = 20, hueShift: Double = 0, saturation: Double = 0,
                luminance: Double = 0) {
        self.id = id
        self.name = name
        self.centerHue = centerHue
        self.width = width
        self.falloff = falloff
        self.hueShift = hueShift
        self.saturation = saturation
        self.luminance = luminance
    }

    public var isNeutral: Bool { hueShift == 0 && saturation == 0 && luminance == 0 }

    func weight(for hue: Double) -> Double {
        let center = TargetedColorTools.wrapDegrees(centerHue)
        let value = TargetedColorTools.wrapDegrees(hue)
        let direct = abs(value - center)
        let distance = min(direct, 360 - direct)
        let core = min(180, max(0, width.isFinite ? width : 0)) / 2
        if distance <= core { return 1 }
        let feather = min(180, max(0, falloff.isFinite ? falloff : 0))
        guard feather > 0, distance < core + feather else { return 0 }
        let progress = (distance - core) / feather
        return 1 - progress * progress * (3 - 2 * progress)
    }
}

public enum TargetedColorPreset: String, CaseIterable, Identifiable {
    case red = "Red"
    case orange = "Orange"
    case yellow = "Yellow"
    case green = "Green"
    case cyan = "Cyan"
    case blue = "Blue"
    case magenta = "Magenta"

    public var id: Self { self }

    public var centerHue: Double {
        switch self {
        case .red: 0
        case .orange: 30
        case .yellow: 60
        case .green: 120
        case .cyan: 180
        case .blue: 240
        case .magenta: 300
        }
    }

    public func adjustment() -> TargetedColorAdjustment {
        TargetedColorAdjustment(name: rawValue, centerHue: centerHue)
    }
}

public struct TargetedColorSample: Equatable {
    public let red: Int
    public let green: Int
    public let blue: Int
    public let hue: Double
    public let saturation: Double
    public let luminance: Double
}

enum TargetedColorTools {
    static func wrapDegrees(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder < 0 ? remainder + 360 : remainder
    }

    static func hsl(red: Double, green: Double, blue: Double) -> (hue: Double, saturation: Double, luminance: Double) {
        let maximum = max(red, green, blue), minimum = min(red, green, blue)
        let luminance = (maximum + minimum) / 2
        let delta = maximum - minimum
        guard delta > 0 else { return (0, 0, luminance) }
        let saturation = delta / (1 - abs(2 * luminance - 1))
        let sector: Double
        if maximum == red {
            sector = ((green - blue) / delta).truncatingRemainder(dividingBy: 6)
        } else if maximum == green {
            sector = (blue - red) / delta + 2
        } else {
            sector = (red - green) / delta + 4
        }
        return (wrapDegrees(sector * 60), saturation, luminance)
    }

    static func rgb(hue: Double, saturation: Double, luminance: Double) -> (red: Double, green: Double, blue: Double) {
        let hue = wrapDegrees(hue)
        let saturation = min(1, max(0, saturation))
        let luminance = min(1, max(0, luminance))
        let chroma = (1 - abs(2 * luminance - 1)) * saturation
        let sector = hue / 60
        let intermediate = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let channels: (Double, Double, Double)
        switch sector {
        case 0..<1: channels = (chroma, intermediate, 0)
        case 1..<2: channels = (intermediate, chroma, 0)
        case 2..<3: channels = (0, chroma, intermediate)
        case 3..<4: channels = (0, intermediate, chroma)
        case 4..<5: channels = (intermediate, 0, chroma)
        default: channels = (chroma, 0, intermediate)
        }
        let match = luminance - chroma / 2
        return (channels.0 + match, channels.1 + match, channels.2 + match)
    }

    static func signed(_ original: Double, amount: Double) -> Double {
        let amount = min(1, max(-1, amount))
        return amount >= 0 ? original + (1 - original) * amount : original * (1 + amount)
    }
}

public extension Renderer {
    static func applyTargetedColors(_ source: CGImage, targets: [TargetedColorAdjustment]) throws -> CGImage {
        let active = targets.filter { !$0.isNeutral }
        guard !active.isEmpty else { return source }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: source.width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw LibraryError.unsupportedImage("targeted color") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4)
        for y in 0..<source.height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<source.width {
                let offset = (y * source.width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let red = Double(pixels[offset]) / (255 * alpha)
                let green = Double(pixels[offset + 1]) / (255 * alpha)
                let blue = Double(pixels[offset + 2]) / (255 * alpha)
                let hsl = TargetedColorTools.hsl(red: red, green: green, blue: blue)
                guard hsl.saturation > 0.000_001 else { continue }
                var hueShift = 0.0, saturation = 0.0, luminance = 0.0
                for target in active {
                    let weight = target.weight(for: hsl.hue)
                    guard weight > 0 else { continue }
                    hueShift += min(180, max(-180, target.hueShift.isFinite ? target.hueShift : 0)) * weight
                    saturation += min(1, max(-1, target.saturation.isFinite ? target.saturation : 0)) * weight
                    luminance += min(1, max(-1, target.luminance.isFinite ? target.luminance : 0)) * weight
                }
                guard hueShift != 0 || saturation != 0 || luminance != 0 else { continue }
                let output = TargetedColorTools.rgb(
                    hue: hsl.hue + min(180, max(-180, hueShift)),
                    saturation: TargetedColorTools.signed(hsl.saturation, amount: saturation),
                    luminance: TargetedColorTools.signed(hsl.luminance, amount: luminance))
                pixels[offset] = UInt8((min(1, max(0, output.red)) * alpha * 255).rounded())
                pixels[offset + 1] = UInt8((min(1, max(0, output.green)) * alpha * 255).rounded())
                pixels[offset + 2] = UInt8((min(1, max(0, output.blue)) * alpha * 255).rounded())
            }
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("targeted color") }
        return result
    }

    /// Samples an opaque chromatic source pixel before targeted colour and downstream Levels/Curves.
    static func sampleTargetedColor(_ url: URL, adjustments: Adjustments,
                                    viewerPoint: CGPoint) throws -> TargetedColorSample? {
        guard (0...1).contains(viewerPoint.x), (0...1).contains(viewerPoint.y) else { return nil }
        let (image, geometry) = try renderToneInput(url, adjustments: adjustments, maxDimension: nil)
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
        let hsl = TargetedColorTools.hsl(red: Double(channels[0]) / 255,
                                         green: Double(channels[1]) / 255,
                                         blue: Double(channels[2]) / 255)
        guard hsl.saturation >= 0.02 else { return nil }
        return TargetedColorSample(red: channels[0], green: channels[1], blue: channels[2],
                                   hue: hsl.hue, saturation: hsl.saturation, luminance: hsl.luminance)
    }
}
