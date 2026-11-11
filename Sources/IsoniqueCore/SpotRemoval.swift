import Foundation
import CoreGraphics

public enum SpotRemovalMode: String, Codable, CaseIterable, Identifiable {
    case repair = "Repair"
    case clone = "Clone"
    public var id: Self { self }
}

/// A non-destructive circular patch in the EXIF-oriented source image.
public struct SpotRemoval: Codable, Equatable, Identifiable {
    public var id: UUID
    public var mode: SpotRemovalMode
    public var source: BrushPoint
    public var destination: BrushPoint
    /// Radius as a fraction of the shorter side of the oriented source.
    public var radius: Double

    public init(id: UUID = UUID(), mode: SpotRemovalMode, source: BrushPoint,
                destination: BrushPoint, radius: Double) {
        self.id = id
        self.mode = mode
        self.source = source
        self.destination = destination
        self.radius = radius
    }

    public var isValid: Bool {
        (0.0025...0.25).contains(radius) &&
            [source.x, source.y, destination.x, destination.y].allSatisfy { $0.isFinite && (0...1).contains($0) }
    }
}

extension Renderer {
    static func applySpotRemovals(_ source: CGImage, spots: [SpotRemoval]) throws -> CGImage {
        let valid = spots.filter(\.isValid)
        guard !valid.isEmpty else { return source }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: source.width * 4,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue),
              let contextData = context.data else { throw LibraryError.unsupportedImage("spot removal") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let count = source.width * source.height * 4
        let output = contextData.bindMemory(to: UInt8.self, capacity: count)

        for spot in valid {
            try Task.checkCancellation()
            let snapshot = [UInt8](UnsafeBufferPointer(start: output, count: count))
            try apply(spot, snapshot: snapshot, output: output, width: source.width, height: source.height)
        }
        guard let image = context.makeImage() else { throw LibraryError.unsupportedImage("spot removal") }
        return image
    }

    private static func apply(_ spot: SpotRemoval, snapshot: [UInt8], output: UnsafeMutablePointer<UInt8>,
                              width: Int, height: Int) throws {
        let shortEdge = Double(min(width, height))
        let radius = max(1, spot.radius * shortEdge)
        let sourceCenter = CGPoint(x: spot.source.x * Double(width), y: spot.source.y * Double(height))
        let destinationCenter = CGPoint(x: spot.destination.x * Double(width), y: spot.destination.y * Double(height))
        let x0 = max(0, Int(floor(destinationCenter.x - radius)))
        let x1 = min(width, Int(ceil(destinationCenter.x + radius)))
        let y0 = max(0, Int(floor(destinationCenter.y - radius)))
        let y1 = min(height, Int(ceil(destinationCenter.y + radius)))
        guard x0 < x1, y0 < y1 else { return }

        let colourOffset = spot.mode == .repair
            ? localColourOffset(snapshot, source: sourceCenter, destination: destinationCenter,
                                radius: radius * 0.55, width: width, height: height)
            : [0.0, 0.0, 0.0]
        let featherStart = radius * 0.72
        for y in y0..<y1 {
            if y.isMultiple(of: 32) { try Task.checkCancellation() }
            for x in x0..<x1 {
                let dx = Double(x) + 0.5 - destinationCenter.x
                let dy = Double(y) + 0.5 - destinationCenter.y
                let distance = hypot(dx, dy)
                guard distance <= radius else { continue }
                let sourcePixel = sample(snapshot, x: sourceCenter.x + dx - 0.5,
                                         y: sourceCenter.y + dy - 0.5, width: width, height: height)
                let index = (y * width + x) * 4
                let destination = (0..<4).map { Double(snapshot[index + $0]) }
                let coverage: Double
                if distance <= featherStart { coverage = 1 }
                else {
                    let amount = max(0, min(1, (radius - distance) / (radius - featherStart)))
                    coverage = amount * amount * (3 - 2 * amount)
                }
                let sourceAlpha = sourcePixel[3] / 255
                let destinationAlpha = destination[3] / 255
                let alpha = sourceAlpha * coverage + destinationAlpha * (1 - coverage)
                for channel in 0..<3 {
                    let straightSource = sourceAlpha > 0 ? sourcePixel[channel] / sourceAlpha : 0
                    let adjusted = max(0, min(255, straightSource + colourOffset[channel]))
                    let candidate = adjusted * sourceAlpha
                    output[index + channel] = UInt8(max(0, min(255,
                        (candidate * coverage + destination[channel] * (1 - coverage)).rounded()
                    )))
                }
                output[index + 3] = UInt8(max(0, min(255, (alpha * 255).rounded())))
            }
        }
    }

    private static func localColourOffset(_ pixels: [UInt8], source: CGPoint, destination: CGPoint,
                                          radius: Double, width: Int, height: Int) -> [Double] {
        guard let sourceMean = localMean(pixels, center: source, innerRadius: 0, outerRadius: radius,
                                         width: width, height: height),
              let destinationMean = localMean(pixels, center: destination, innerRadius: radius * 1.55,
                                              outerRadius: radius * 2.15, width: width, height: height)
                ?? localMean(pixels, center: destination, innerRadius: 0, outerRadius: radius,
                             width: width, height: height) else { return [0, 0, 0] }
        return (0..<3).map { destinationMean[$0] - sourceMean[$0] }
    }

    private static func localMean(_ pixels: [UInt8], center: CGPoint, innerRadius: Double,
                                  outerRadius: Double, width: Int, height: Int) -> [Double]? {
        let extent = max(1, Int(outerRadius.rounded(.up)))
        var total = [Double](repeating: 0, count: 3)
        var count = 0.0
        for offsetY in -extent...extent {
            for offsetX in -extent...extent {
                let distance = hypot(Double(offsetX), Double(offsetY))
                guard distance >= innerRadius, distance <= outerRadius else { continue }
                let x = Int(center.x.rounded(.down)) + offsetX
                let y = Int(center.y.rounded(.down)) + offsetY
                guard x >= 0, x < width, y >= 0, y < height else { continue }
                let index = (y * width + x) * 4
                let alpha = Double(pixels[index + 3]) / 255
                guard alpha > 0 else { continue }
                for channel in 0..<3 { total[channel] += Double(pixels[index + channel]) / alpha }
                count += 1
            }
        }
        return count > 0 ? total.map { $0 / count } : nil
    }

    private static func sample(_ pixels: [UInt8], x: Double, y: Double, width: Int, height: Int) -> [Double] {
        let x = max(0, min(Double(width - 1), x))
        let y = max(0, min(Double(height - 1), y))
        let x0 = Int(floor(x)), y0 = Int(floor(y))
        let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let fx = x - Double(x0), fy = y - Double(y0)
        return (0..<4).map { channel in
            let top = Double(pixels[(y0 * width + x0) * 4 + channel]) * (1 - fx) +
                Double(pixels[(y0 * width + x1) * 4 + channel]) * fx
            let bottom = Double(pixels[(y1 * width + x0) * 4 + channel]) * (1 - fx) +
                Double(pixels[(y1 * width + x1) * 4 + channel]) * fx
            return top * (1 - fy) + bottom * fy
        }
    }
}
