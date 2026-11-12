import Foundation
import CoreGraphics

extension Renderer {
    private struct DetailRGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    static func applyLuminanceNoiseReduction(_ source: CGImage, amount: Double) throws -> CGImage {
        try applyLuminanceNoiseReduction(source, amount: amount, mask: nil)
    }

    static func applyLocalLuminanceNoiseReduction(_ source: CGImage,
                                                   mask: LocalAdjustmentMask?) throws -> CGImage {
        guard mask?.isActive(.noiseReduction) == true else { return source }
        return try applyLuminanceNoiseReduction(source, amount: 1, mask: mask)
    }

    private static func applyLuminanceNoiseReduction(_ source: CGImage, amount: Double,
                                                      mask: LocalAdjustmentMask?) throws -> CGImage {
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
                    let localAmount = amount * (mask?.coverage(for: .noiseReduction, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 1)
                    let delta = (total / totalWeight - current) * localAmount
                    writeLuminanceDelta(delta, channels: channels, alpha: alpha, pixels: pixels, offset: offset)
                }
            }
        }
    }

    static func applySharpening(_ source: CGImage, sharpening: Double, edgeSharpening: Double) throws -> CGImage {
        try applySharpening(source, sharpening: sharpening, edgeSharpening: edgeSharpening, mask: nil)
    }

    static func applyLocalSharpening(_ source: CGImage, mask: LocalAdjustmentMask?) throws -> CGImage {
        guard mask?.isActive(.sharpening) == true else { return source }
        return try applySharpening(source, sharpening: 1, edgeSharpening: 0, mask: mask)
    }

    static func applyLocalContrast(_ source: CGImage, mask: LocalAdjustmentMask?) throws -> CGImage {
        guard mask?.isActive(.contrast) == true else { return source }
        return try withDetailPixels(source, operation: "local contrast") { pixels, width, height in
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let amount = mask?.coverage(for: .contrast, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 0
                    guard amount > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let current = luminance(channels)
                    let pivot = 128.0 / 255
                    let target = pivot + (current - pivot) * (1 + amount)
                    writeLuminanceDelta(target - current, channels: channels, alpha: alpha,
                                        pixels: pixels, offset: offset)
                }
            }
        }
    }

    static func applyLocalBlur(_ source: CGImage, mask: LocalAdjustmentMask?) throws -> CGImage {
        guard mask?.isActive(.blur) == true else { return source }
        return try withDetailPixels(source, operation: "local blur") { pixels, width, height in
            var blurred = [Float](repeating: 0, count: width * height)
            var temporary = blurred
            try blurredLuminance(pixels, width: width, height: height,
                                 output: &blurred, temporary: &temporary)
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let amount = mask?.coverage(for: .blur, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 0
                    guard amount > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let current = luminance(channels)
                    let delta = (Double(blurred[y * width + x]) - current) * amount
                    writeLuminanceDelta(delta, channels: channels, alpha: alpha,
                                        pixels: pixels, offset: offset)
                }
            }
        }
    }

    static func applyLocalTint(_ source: CGImage, settings: LocalTintSettings,
                               mask: LocalAdjustmentMask?) throws -> CGImage {
        let saturation = settings.boundedSaturation
        guard saturation > 0, mask?.isActive(.tint) == true else { return source }
        let hue = settings.boundedHue
        return try withDetailPixels(source, operation: "local tint") { pixels, width, height in
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let amount = saturation * (mask?.coverage(for: .tint, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 0)
                    guard amount > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let target = tintTarget(hue: hue, lightness: (max(channels.red, channels.green,
                        channels.blue) + min(channels.red, channels.green, channels.blue)) / 2)
                    writeChannels(DetailRGB(red: channels.red + (target.red - channels.red) * amount,
                                           green: channels.green + (target.green - channels.green) * amount,
                                           blue: channels.blue + (target.blue - channels.blue) * amount),
                                  alpha: alpha, pixels: pixels, offset: offset)
                }
            }
        }
    }

    static func applyLocalSkinSmoothing(_ source: CGImage, settings: LocalSkinSmoothingSettings,
                                        mask: LocalAdjustmentMask?) throws -> CGImage {
        let amount = settings.boundedAmount
        guard amount > 0, mask?.isActive(.skinSmoothing) == true else { return source }
        let preservation = settings.boundedDetailPreservation
        return try withDetailPixels(source, operation: "local skin smoothing") { pixels, width, height in
            var blurred = [Float](repeating: 0, count: width * height)
            var temporary = blurred
            try blurredLuminance(pixels, width: width, height: height,
                                 output: &blurred, temporary: &temporary)
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let skin = skinToneWeight(channels)
                    guard skin > 0 else { continue }
                    let current = luminance(channels)
                    let blurredValue = Double(blurred[y * width + x])
                    let detail = smoothstep(min(1, abs(current - blurredValue) / 0.08))
                    let coverage = mask?.coverage(for: .skinSmoothing, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 0
                    let effectiveAmount = coverage * amount * skin * (1 - preservation * detail)
                    writeLuminanceDelta((blurredValue - current) * effectiveAmount,
                                        channels: channels, alpha: alpha, pixels: pixels, offset: offset)
                }
            }
        }
    }

    static func applyLocalPolarize(_ source: CGImage, settings: LocalPolarizeSettings,
                                   mask: LocalAdjustmentMask?) throws -> CGImage {
        let intensity = settings.boundedIntensity
        guard intensity > 0, mask?.isActive(.polarize) == true else { return source }
        return try withDetailPixels(source, operation: "local polarize") { pixels, width, height in
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let coverage = mask?.coverage(for: .polarize, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 0
                    guard coverage > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let hsl = TargetedColorTools.hsl(red: channels.red, green: channels.green,
                                                     blue: channels.blue)
                    guard hsl.saturation > 0.08 else { continue }
                    let hueDistance = min(abs(hsl.hue - 215), 360 - abs(hsl.hue - 215))
                    guard hueDistance < 75 else { continue }
                    let hueWeight = 1 - smoothstep(min(1, hueDistance / 75))
                    let saturationWeight = smoothstep(min(1, max(0, (hsl.saturation - 0.08) / 0.35)))
                    let amount = intensity * coverage * hueWeight * saturationWeight
                    guard amount > 0 else { continue }
                    let output = TargetedColorTools.rgb(
                        hue: hsl.hue,
                        saturation: TargetedColorTools.signed(hsl.saturation, amount: amount * 0.4),
                        luminance: TargetedColorTools.signed(hsl.luminance, amount: -amount * 0.22))
                    writeChannels(DetailRGB(red: output.red, green: output.green, blue: output.blue),
                                  alpha: alpha, pixels: pixels, offset: offset)
                }
            }
        }
    }

    static func applyLocalHaloReduction(_ source: CGImage, settings: LocalHaloReductionSettings,
                                        mask: LocalAdjustmentMask?) throws -> CGImage {
        let amount = settings.boundedAmount
        guard amount > 0, mask?.isActive(.haloReduction) == true else { return source }
        return try withDetailPixels(source, operation: "local halo reduction") { pixels, width, height in
            let radius = max(1, Int((Double(min(width, height)) * settings.boundedRadius).rounded()))
            var blurred = [Float](repeating: 0, count: width * height)
            var temporary = blurred
            try boxBlurredLuminance(pixels, width: width, height: height, radius: radius,
                                    output: &blurred, temporary: &temporary)
            for y in 0..<height {
                if y.isMultiple(of: 64) { try Task.checkCancellation() }
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    let alpha = Double(pixels[offset + 3]) / 255
                    guard alpha > 0 else { continue }
                    let coverage = mask?.coverage(for: .haloReduction, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 0
                    guard coverage > 0 else { continue }
                    let channels = straightChannels(pixels, offset: offset, alpha: alpha)
                    let current = luminance(channels)
                    let localMean = Double(blurred[y * width + x])
                    let highPass = current - localMean
                    let haloWeight = smoothstep(min(1, max(0, (abs(highPass) - 0.015) / 0.12)))
                    guard haloWeight > 0 else { continue }
                    writeLuminanceDelta(-highPass * amount * coverage * haloWeight,
                                        channels: channels, alpha: alpha, pixels: pixels, offset: offset)
                }
            }
        }
    }

    private static func applySharpening(_ source: CGImage, sharpening: Double, edgeSharpening: Double,
                                        mask: LocalAdjustmentMask?) throws -> CGImage {
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
                    let localAmount = mask?.coverage(for: .sharpening, x: x, y: y,
                        imageWidth: width, imageHeight: height) ?? 1
                    let gain = (sharpening * 1.6 + edgeSharpening * 2.2 * edgeMask) * localAmount
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

    private static func boxBlurredLuminance(_ pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
                                            radius: Int, output: inout [Float],
                                            temporary: inout [Float]) throws {
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
            var sum = 0.0
            var count = 0
            for x in 0..<width {
                let entering = x + radius
                if entering < width { sum += Double(output[y * width + entering]); count += 1 }
                if x == 0 {
                    for initial in 0..<min(radius, width) {
                        sum += Double(output[y * width + initial]); count += 1
                    }
                } else {
                    let leaving = x - radius - 1
                    if leaving >= 0 { sum -= Double(output[y * width + leaving]); count -= 1 }
                }
                temporary[y * width + x] = Float(sum / Double(max(1, count)))
            }
        }
        for x in 0..<width {
            var sum = 0.0
            var count = 0
            for y in 0..<height {
                let entering = y + radius
                if entering < height { sum += Double(temporary[entering * width + x]); count += 1 }
                if y == 0 {
                    for initial in 0..<min(radius, height) {
                        sum += Double(temporary[initial * width + x]); count += 1
                    }
                } else {
                    let leaving = y - radius - 1
                    if leaving >= 0 { sum -= Double(temporary[leaving * width + x]); count -= 1 }
                }
                output[y * width + x] = Float(sum / Double(max(1, count)))
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

    private static func tintTarget(hue: Double, lightness: Double) -> DetailRGB {
        let chroma = max(0, 1 - abs(2 * lightness - 1))
        let sector = hue / 60
        let secondary = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
        let channels: (Double, Double, Double)
        switch sector {
        case 0..<1: channels = (chroma, secondary, 0)
        case 1..<2: channels = (secondary, chroma, 0)
        case 2..<3: channels = (0, chroma, secondary)
        case 3..<4: channels = (0, secondary, chroma)
        case 4..<5: channels = (secondary, 0, chroma)
        default: channels = (chroma, 0, secondary)
        }
        let match = lightness - chroma / 2
        return DetailRGB(red: channels.0 + match, green: channels.1 + match, blue: channels.2 + match)
    }

    private static func skinToneWeight(_ channels: DetailRGB) -> Double {
        let maximum = max(channels.red, channels.green, channels.blue)
        let minimum = min(channels.red, channels.green, channels.blue)
        let delta = maximum - minimum
        guard delta > 0.04, channels.red > channels.green, channels.green > channels.blue * 0.82 else { return 0 }
        var hue = 60 * ((channels.green - channels.blue) / delta).truncatingRemainder(dividingBy: 6)
        if hue < 0 { hue += 360 }
        let saturation = maximum > 0 ? delta / maximum : 0
        let light = (maximum + minimum) / 2
        guard hue <= 55, (0.12...0.75).contains(saturation), (0.15...0.92).contains(light) else { return 0 }
        let hueWeight = 1 - smoothstep(min(1, max(0, (hue - 35) / 20)))
        return max(0.25, hueWeight)
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

    private static func writeChannels(_ channels: DetailRGB, alpha: Double,
                                      pixels: UnsafeMutablePointer<UInt8>, offset: Int) {
        func encoded(_ value: Double) -> UInt8 {
            UInt8((min(1, max(0, value)) * alpha * 255).rounded())
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
