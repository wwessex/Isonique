import Foundation
import CoreGraphics

extension Renderer {
    private struct DetailRGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    static func applyLuminanceNoiseReduction(_ source: CGImage, amount: Double) throws -> CGImage {
        let amount = boundedDetail(amount)
        guard amount > 0 else { return source }
        return try withDetailPixels(source, operation: "luminance noise reduction") { pixels, width, height in
            let snapshot = [UInt8](UnsafeBufferPointer(start: pixels, count: width * height * 4))
            let neighbours = [(-1, 0), (1, 0), (0, -1), (0, 1)]
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let current = luminance(channels)
                    var total = current * 2
                    var totalWeight = 2.0
                    for (deltaX, deltaY) in neighbours {
                        let sampleX = min(width - 1, max(0, x + deltaX))
                        let sampleY = min(height - 1, max(0, y + deltaY))
                        guard let neighbor = snapshotLuminance(snapshot, x: sampleX, y: sampleY,
                                                               width: width) else { continue }
                        let weight = max(0, 1 - abs(neighbor - current) / 0.25)
                        total += neighbor * weight
                        totalWeight += weight
                    }
                    let delta = (total / totalWeight - current) * amount
                    writeLuminanceDelta(delta, channels: channels, alpha: alpha, pixels: pixels, offset: offset)
                }
            }
        }
    }

    static func applySharpening(_ source: CGImage, sharpening: Double, edgeSharpening: Double) throws -> CGImage {
        let sharpening = boundedDetail(sharpening)
        let edgeSharpening = boundedDetail(edgeSharpening)
        guard sharpening > 0 || edgeSharpening > 0 else { return source }
        return try withDetailPixels(source, operation: "sharpening") { pixels, width, height in
            var blurred = [Float](repeating: 0, count: width * height)
            var temporary = blurred
            try blurredLuminance(pixels, width: width, height: height, output: &blurred, temporary: &temporary)
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let current = luminance(channels)
                    let highPass = current - Double(blurred[y * width + x])
                    let edgeMask = smoothstep(min(1, abs(highPass) / 0.08))
                    let gain = sharpening * 1.6 + edgeSharpening * 2.2 * edgeMask
                    writeLuminanceDelta(highPass * gain, channels: channels, alpha: alpha,
                                        pixels: pixels, offset: offset)
                }
            }
        }
    }

    private static func withDetailPixels(_ source: CGImage, operation: String,
                                         _ transform: (UnsafeMutablePointer<UInt8>, Int, Int) throws -> Void) throws -> CGImage {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw LibraryError.unsupportedImage(operation) }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        try transform(data.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4),
                      source.width, source.height)
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage(operation) }
        return result
    }

    private static func blurredLuminance(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
                                         output: inout [Float], temporary: inout [Float]) throws {
        guard width > 0, height > 0 else { return }
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                output[y * width + x] = alpha > 0
                    ? Float(luminance(straightChannels(pixels, offset: offset, alpha: alpha))) : 0
            }
        }
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<width {
                let left = output[y * width + max(0, x - 1)]
                let center = output[y * width + x]
                let right = output[y * width + min(width - 1, x + 1)]
                temporary[y * width + x] = (left + 2 * center + right) / 4
            }
        }
        for y in 0..<height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            let above = max(0, y - 1), below = min(height - 1, y + 1)
            for x in 0..<width {
                output[y * width + x] = (temporary[above * width + x] +
                                         2 * temporary[y * width + x] +
                                         temporary[below * width + x]) / 4
            }
        }
    }

    private static func straightChannels(_ pixels: UnsafeMutablePointer<UInt8>, offset: Int,
                                         alpha: Double) -> DetailRGB {
        DetailRGB(red: Double(pixels[offset]) / (255 * alpha),
                  green: Double(pixels[offset + 1]) / (255 * alpha),
                  blue: Double(pixels[offset + 2]) / (255 * alpha))
    }

    private static func luminance(_ channels: DetailRGB) -> Double {
        0.2126 * channels.red + 0.7152 * channels.green + 0.0722 * channels.blue
    }

    private static func snapshotLuminance(_ pixels: [UInt8], x: Int, y: Int, width: Int) -> Double? {
        let offset = (y * width + x) * 4
        let alpha = Double(pixels[offset + 3]) / 255
        guard alpha > 0 else { return nil }
        let red = Double(pixels[offset]) / (255 * alpha)
        let green = Double(pixels[offset + 1]) / (255 * alpha)
        let blue = Double(pixels[offset + 2]) / (255 * alpha)
        return 0.2126 * red + 0.7152 * green + 0.0722 * blue
    }

    private static func writeLuminanceDelta(_ delta: Double, channels: DetailRGB, alpha: Double,
                                            pixels: UnsafeMutablePointer<UInt8>, offset: Int) {
        func encoded(_ value: Double) -> UInt8 {
            UInt8((min(1, max(0, value + delta)) * alpha * 255).rounded())
        }
        pixels[offset] = encoded(channels.red)
        pixels[offset + 1] = encoded(channels.green)
        pixels[offset + 2] = encoded(channels.blue)
    }

    private static func boundedDetail(_ amount: Double) -> Double {
        amount.isFinite ? min(1, max(0, amount)) : 0
    }

    private static func smoothstep(_ value: Double) -> Double {
        value * value * (3 - 2 * value)
    }
}
