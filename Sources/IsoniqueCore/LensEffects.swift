import Foundation
import CoreGraphics

extension Renderer {
    static func applyChromaticAberration(_ source: CGImage, redCyan: Double, blueYellow: Double) throws -> CGImage {
        let redCyan = boundedSigned(redCyan)
        let blueYellow = boundedSigned(blueYellow)
        guard redCyan != 0 || blueYellow != 0 else { return source }
        let width = source.width, height = source.height
        let count = width * height * 4
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let contextData = context.data else { throw LibraryError.unsupportedImage("chromatic aberration") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let output = contextData.bindMemory(to: UInt8.self, capacity: count)
        let snapshot = [UInt8](UnsafeBufferPointer(start: output, count: count))
        let redScale = 1 + redCyan * 0.004
        let blueScale = 1 + blueYellow * 0.004
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            let normalizedY = (Double(y) + 0.5) / Double(height) - 0.5
            for x in 0..<width {
                let normalizedX = (Double(x) + 0.5) / Double(width) - 0.5
                let offset = (y * width + x) * 4
                let destinationAlpha = Double(snapshot[offset + 3]) / 255
                guard destinationAlpha > 0 else { continue }
                if redCyan != 0 {
                    output[offset] = sampledChannel(snapshot, channel: 0,
                        x: (0.5 + normalizedX * redScale) * Double(width) - 0.5,
                        y: (0.5 + normalizedY * redScale) * Double(height) - 0.5,
                        width: width, height: height, destinationAlpha: destinationAlpha)
                }
                if blueYellow != 0 {
                    output[offset + 2] = sampledChannel(snapshot, channel: 2,
                        x: (0.5 + normalizedX * blueScale) * Double(width) - 0.5,
                        y: (0.5 + normalizedY * blueScale) * Double(height) - 0.5,
                        width: width, height: height, destinationAlpha: destinationAlpha)
                }
            }
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("chromatic aberration") }
        return result
    }

    static func applyDevignette(_ source: CGImage, amount: Double) throws -> CGImage {
        try applyRadialIllumination(source, amount: boundedUnit(amount), brightening: true)
    }

    static func applyVignette(_ source: CGImage, amount: Double) throws -> CGImage {
        try applyRadialIllumination(source, amount: boundedUnit(amount), brightening: false)
    }

    private static func applyRadialIllumination(_ source: CGImage, amount: Double,
                                                brightening: Bool) throws -> CGImage {
        guard amount > 0 else { return source }
        let width = source.width, height = source.height
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let contextData = context.data else { throw LibraryError.unsupportedImage("vignette") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = contextData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            let ny = (Double(y) + 0.5) / Double(height) * 2 - 1
            for x in 0..<width {
                let nx = (Double(x) + 0.5) / Double(width) * 2 - 1
                let radius = min(1, hypot(nx, ny) / sqrt(2))
                let position = min(1, max(0, (radius - 0.12) / 0.88))
                let mask = position * position * (3 - 2 * position)
                let gain = brightening ? 1 + amount * 1.2 * mask : 1 - amount * 0.85 * mask
                let offset = (y * width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0 else { continue }
                for channel in 0..<3 {
                    let straight = Double(pixels[offset + channel]) / (255 * alpha)
                    pixels[offset + channel] = UInt8((min(1, max(0, straight * gain)) * alpha * 255).rounded())
                }
            }
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("vignette") }
        return result
    }

    private static func sampledChannel(_ pixels: [UInt8], channel: Int, x: Double, y: Double,
                                       width: Int, height: Int, destinationAlpha: Double) -> UInt8 {
        let x = min(Double(width - 1), max(0, x)), y = min(Double(height - 1), max(0, y))
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let fx = x - Double(x0), fy = y - Double(y0)
        func interpolated(_ component: Int) -> Double {
            let top = Double(pixels[(y0 * width + x0) * 4 + component]) * (1 - fx) +
                Double(pixels[(y0 * width + x1) * 4 + component]) * fx
            let bottom = Double(pixels[(y1 * width + x0) * 4 + component]) * (1 - fx) +
                Double(pixels[(y1 * width + x1) * 4 + component]) * fx
            return top * (1 - fy) + bottom * fy
        }
        let sampledAlpha = interpolated(3) / 255
        guard sampledAlpha > 0 else { return 0 }
        let straight = interpolated(channel) / (255 * sampledAlpha)
        return UInt8((min(1, max(0, straight)) * destinationAlpha * 255).rounded())
    }

    private static func boundedSigned(_ value: Double) -> Double {
        value.isFinite ? min(1, max(-1, value)) : 0
    }

    private static func boundedUnit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
