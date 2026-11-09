import Foundation
import CoreGraphics

public extension Renderer {
    /// ICC round-trip simulation for RGB output profiles, relative colorimetric intent.
    /// Preview only; exports retain their normal sRGB rendering.
    static func proof(_ image: CGImage, profile: Data) throws -> CGImage {
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let space = CGColorSpace(iccData: profile as CFData), space.model == .rgb,
              let proofContext = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info),
              let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let displayContext = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: info) else { throw CocoaError(.fileReadCorruptFile) }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        proofContext.setRenderingIntent(.relativeColorimetric)
        proofContext.draw(image, in: rect)
        guard let converted = proofContext.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        displayContext.setRenderingIntent(.relativeColorimetric)
        displayContext.draw(converted, in: rect)
        guard let result = displayContext.makeImage() else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }
    /// Independent radial correction with edge clamping, before crop/rotation.
    static func applyLens(_ image: CGImage, amount: Double) throws -> CGImage {
        guard amount.isFinite, amount != 0 else { return image }
        let width = image.width, height = image.height
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let source = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info),
              let output = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space, bitmapInfo: info),
              let sourceData = source.data, let outputData = output.data else { throw CocoaError(.coderInvalidValue) }
        source.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let src = sourceData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let dst = outputData.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let k = min(1, max(-1, amount)) * 0.35
        for y in 0..<height { for x in 0..<width {
            let point = PhotoGeometry.lensSourcePoint(x: (Double(x) + 0.5) / Double(width),
                                                       y: (Double(y) + 0.5) / Double(height), coefficient: k)
            let sx = min(Double(width - 1), max(0, point.x * Double(width) - 0.5))
            let sy = min(Double(height - 1), max(0, point.y * Double(height) - 0.5))
            let x0 = Int(sx), y0 = Int(sy), x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
            let fx = sx - Double(x0), fy = sy - Double(y0)
            for c in 0..<4 {
                let top = Double(src[(y0 * width + x0) * 4 + c]) * (1 - fx) + Double(src[(y0 * width + x1) * 4 + c]) * fx
                let bottom = Double(src[(y1 * width + x0) * 4 + c]) * (1 - fx) + Double(src[(y1 * width + x1) * 4 + c]) * fx
                dst[(y * width + x) * 4 + c] = UInt8(min(255, max(0, (top * (1 - fy) + bottom * fy).rounded())))
            }
        } }
        guard let result = output.makeImage() else { throw CocoaError(.coderInvalidValue) }
        return result
    }
}
