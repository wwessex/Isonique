import Foundation
import CoreGraphics

public enum SlideshowRules {
    public static let defaultDisplayTime = 3.0
}

/// Independent 8-bit sRGB levels and piecewise-linear master curve.
public enum TonalTools {
    public static func map(_ input: Double, adjustments a: Adjustments) -> Double {
        func safe(_ value: Double, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        let black = safe(a.blackPoint, 0, 0...0.99)
        let white = max(black + 0.001, safe(a.whitePoint, 1, 0.01...1))
        let x = pow(min(1, max(0, (input - black) / (white - black))), 1 / safe(a.gamma, 1, 0.1...4))
        let points = [0, safe(a.curveShadows, 0.25, 0...1), safe(a.curveMidtones, 0.5, 0...1), safe(a.curveHighlights, 0.75, 0...1), 1]
        let segment = min(3, Int(x * 4)); let fraction = x * 4 - Double(segment)
        return points[segment] + (points[segment + 1] - points[segment]) * fraction
    }
    static func applying(_ image: CGImage, table: [Double], curves: ChannelCurves? = nil) throws -> CGImage {
        let context = try bitmap(image)
        guard let data = context.data else { throw LibraryError.unsupportedImage("levels") }
        let bytes = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let luminance = curves?.luminance.map(LuminanceCurve.init)
        func channelTable(_ curve: ChannelCurve?) -> [Double] {
            let mapped = curve.map { curve in table.map { curve.value(at: $0) } } ?? table
            return luminance == nil ? mapped : mapped.map(linearSRGB)
        }
        let red = channelTable(curves?.red)
        let green = channelTable(curves?.green)
        let blue = channelTable(curves?.blue)
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            if offset.isMultiple(of: 65_536) { try Task.checkCancellation() }
            let alphaByte = Double(bytes[offset + 3])
            guard alphaByte > 0 else { continue }
            let alpha = alphaByte / 255
            let r = red[min(255, Int((Double(bytes[offset]) / alpha).rounded()))]
            let g = green[min(255, Int((Double(bytes[offset + 1]) / alpha).rounded()))]
            let b = blue[min(255, Int((Double(bytes[offset + 2]) / alpha).rounded()))]
            let output = luminance?.apply(r, g, b) ?? (r, g, b)
            bytes[offset] = UInt8((output.0 * alpha * 255).rounded())
            bytes[offset + 1] = UInt8((output.1 * alpha * 255).rounded())
            bytes[offset + 2] = UInt8((output.2 * alpha * 255).rounded())
        }
        guard let output = context.makeImage() else { throw LibraryError.unsupportedImage("levels") }
        return output
    }

    private static func linearSRGB(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    private static func encodedSRGB(_ value: Double) -> Double {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }

    private struct LuminanceCurve {
        private static let resolution = 4096
        private static let encoded = (0...resolution).map { min(1, encodedSRGB(Double($0) / Double(resolution))) }
        let targets: [Double]

        init(_ curve: ChannelCurve) {
            targets = Self.encoded.map { linearSRGB(curve.value(at: $0)) }
        }

        private static func index(_ value: Double) -> Int {
            min(resolution, max(0, Int((value * Double(resolution)).rounded())))
        }

        func apply(_ red: Double, _ green: Double, _ blue: Double) -> (Double, Double, Double) {
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            let target = targets[Self.index(luminance)]
            // Blend toward black or white in linear light to reach the requested luminance within gamut.
            let darkening = target < luminance
            let amount = darkening ? target / max(luminance, .leastNonzeroMagnitude)
                : (1 - target) / max(1 - luminance, .leastNonzeroMagnitude)
            let offset = darkening ? 0 : 1 - amount
            return (Self.encoded[Self.index(red * amount + offset)],
                    Self.encoded[Self.index(green * amount + offset)],
                    Self.encoded[Self.index(blue * amount + offset)])
        }
    }
    public static func histogram(_ image: CGImage) throws -> [Int] {
        let context = try bitmap(image)
        guard let data = context.data else { throw LibraryError.unsupportedImage("histogram") }
        let bytes = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        var bins = [Int](repeating: 0, count: 256)
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            let alpha = Double(bytes[offset + 3]) / 255
            guard alpha > 0 else { continue }
            let value = (0.2126 * Double(bytes[offset]) + 0.7152 * Double(bytes[offset + 1]) + 0.0722 * Double(bytes[offset + 2])) / alpha
            bins[min(255, max(0, Int(value.rounded())))] += 1
        }
        return bins
    }
    private static func bitmap(_ image: CGImage) throws -> CGContext {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { throw LibraryError.unsupportedImage("tone buffer") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context
    }
}

public enum AutoStack {
    /// Consecutive capture gaps; absent/invalid dates and existing stacks are excluded.
    public static func groups(_ photos: [Photo], seconds: Double) -> [[UUID]] {
        guard seconds.isFinite, seconds >= 0 else { return [] }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0); formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"; formatter.isLenient = false
        let dated = photos.filter { $0.stackID == nil }.compactMap { photo -> (Photo, Date)? in
            formatter.date(from: photo.captureDate).map { (photo, $0) }
        }.sorted { $0.1 == $1.1 ? $0.0.id.uuidString < $1.0.id.uuidString : $0.1 < $1.1 }
        var groups: [[UUID]] = []; var current: [UUID] = []; var previous: Date?
        for (photo, date) in dated {
            if let previous, date.timeIntervalSince(previous) > seconds { if current.count > 1 { groups.append(current) }; current = [] }
            current.append(photo.id); previous = date
        }
        if current.count > 1 { groups.append(current) }
        return groups
    }
}
