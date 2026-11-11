import Foundation
import CoreGraphics
import ImageIO

public enum LocalBrushAdjustment: String, Codable, CaseIterable, Identifiable {
    case dodge = "Dodge"
    case burn = "Burn"
    public var id: Self { self }
}

/// Normalized coordinates in the EXIF-oriented original, before geometric edits.
public struct BrushPoint: Codable, Equatable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct LocalBrushStroke: Codable, Equatable {
    public let adjustment: LocalBrushAdjustment
    public let erasing: Bool
    public let radius: Double
    public let softness: Double
    public let strength: Double
    public let edgeAware: Bool
    public let points: [BrushPoint]

    /// Radius is a fraction of the shorter side of the uncropped original.
    public init(adjustment: LocalBrushAdjustment, erasing: Bool = false, radius: Double,
                softness: Double, strength: Double, edgeAware: Bool = false, points: [BrushPoint]) {
        self.adjustment = adjustment
        self.erasing = erasing
        self.radius = radius
        self.softness = softness
        self.strength = strength
        self.edgeAware = edgeAware
        self.points = points
    }

    enum CodingKeys: String, CodingKey {
        case adjustment, erasing, radius, softness, strength, edgeAware, points
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        adjustment = try values.decode(LocalBrushAdjustment.self, forKey: .adjustment)
        erasing = try values.decodeIfPresent(Bool.self, forKey: .erasing) ?? false
        radius = try values.decode(Double.self, forKey: .radius)
        softness = try values.decode(Double.self, forKey: .softness)
        strength = try values.decode(Double.self, forKey: .strength)
        edgeAware = try values.decodeIfPresent(Bool.self, forKey: .edgeAware) ?? false
        points = try values.decode([BrushPoint].self, forKey: .points)
    }

    public var isValid: Bool {
        (0.0025...0.25).contains(radius) && (0...1).contains(softness) &&
            (0...1).contains(strength) && strength > 0 && !points.isEmpty &&
            points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }
    }
}

public struct LocalBrushMaskSettings: Codable, Equatable {
    public var opacity: Double
    public var inverted: Bool

    public init(opacity: Double = 1, inverted: Bool = false) {
        self.opacity = opacity
        self.inverted = inverted
    }

    public var isNeutral: Bool { opacity == 1 && !inverted }

    var boundedOpacity: Double { opacity.isFinite ? min(1, max(0, opacity)) : 1 }
}

public extension Adjustments {
    func localBrushSettings(for adjustment: LocalBrushAdjustment) -> LocalBrushMaskSettings {
        localBrushMaskSettings[adjustment] ?? LocalBrushMaskSettings()
    }
}

struct LocalBrushEdgeMap {
    let width: Int
    let height: Int
    let values: [Float]

    init(pixels: UnsafePointer<UInt8>, width: Int, height: Int) {
        self.width = width
        self.height = height
        var values = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let alpha = Double(pixels[offset + 3]) / 255
                guard alpha > 0 else { continue }
                let red = Double(pixels[offset]) / (255 * alpha)
                let green = Double(pixels[offset + 1]) / (255 * alpha)
                let blue = Double(pixels[offset + 2]) / (255 * alpha)
                values[y * width + x] = Float(0.2126 * red + 0.7152 * green + 0.0722 * blue)
            }
        }
        self.values = values
    }

    func luminance(x: Double, y: Double) -> Double {
        let px = min(width - 1, max(0, Int(x * Double(width))))
        let py = min(height - 1, max(0, Int(y * Double(height))))
        return Double(values[py * width + px])
    }
}

/// Bounded mask raster in source space. Each stroke uses maximum coverage along its
/// path, then composites once, so input sampling frequency does not change opacity.
struct LocalExposureMask {
    let width: Int
    let height: Int
    private let masks: [LocalBrushAdjustment: [Float]]
    private let activeAdjustments: Set<LocalBrushAdjustment>
    private let settings: [LocalBrushAdjustment: LocalBrushMaskSettings]

    init?(strokes: [LocalBrushStroke], settings: [LocalBrushAdjustment: LocalBrushMaskSettings] = [:],
          sourceWidth: Int, sourceHeight: Int, edgeMap: LocalBrushEdgeMap? = nil) throws {
        guard strokes.contains(where: { !$0.erasing && $0.isValid }) else { return nil }
        let scale = min(1, 2048 / Double(max(sourceWidth, sourceHeight)))
        width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var dodge = [Float](repeating: 0, count: width * height)
        var burn = dodge
        activeAdjustments = Set(strokes.lazy.filter { !$0.erasing && $0.isValid }.map(\.adjustment))
        for stroke in strokes where stroke.isValid {
            try Task.checkCancellation()
            switch stroke.adjustment {
            case .dodge: try Self.paint(stroke, width: width, height: height, edgeMap: edgeMap, into: &dodge)
            case .burn: try Self.paint(stroke, width: width, height: height, edgeMap: edgeMap, into: &burn)
            }
        }
        masks = [.dodge: dodge, .burn: burn]
        self.settings = settings
    }

    func exposure(x: Int, y: Int, imageWidth: Int, imageHeight: Int) -> Double {
        (coverage(for: .dodge, x: x, y: y, imageWidth: imageWidth, imageHeight: imageHeight) -
            coverage(for: .burn, x: x, y: y, imageWidth: imageWidth, imageHeight: imageHeight)) * 1.5
    }

    func coverage(for adjustment: LocalBrushAdjustment, x: Int, y: Int,
                  imageWidth: Int, imageHeight: Int) -> Double {
        guard activeAdjustments.contains(adjustment), let values = masks[adjustment] else { return 0 }
        let raw: Double
        if width == imageWidth && height == imageHeight {
            raw = Double(values[y * width + x])
        } else {
            let mx = min(Double(width - 1), max(0, (Double(x) + 0.5) * Double(width) / Double(imageWidth) - 0.5))
            let my = min(Double(height - 1), max(0, (Double(y) + 0.5) * Double(height) / Double(imageHeight) - 0.5))
            let x0 = Int(mx), y0 = Int(my)
            let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
            let fx = Float(mx - Double(x0)), fy = Float(my - Double(y0))
            let top = values[y0 * width + x0] * (1 - fx) + values[y0 * width + x1] * fx
            let bottom = values[y1 * width + x0] * (1 - fx) + values[y1 * width + x1] * fx
            raw = Double(top * (1 - fy) + bottom * fy)
        }
        let setting = settings[adjustment] ?? LocalBrushMaskSettings()
        return (setting.inverted ? 1 - raw : raw) * setting.boundedOpacity
    }

    private static func paint(_ stroke: LocalBrushStroke, width: Int, height: Int,
                              edgeMap: LocalBrushEdgeMap?, into mask: inout [Float]) throws {
        let points = stroke.points.map { BrushPoint(x: $0.x * Double(width), y: $0.y * Double(height)) }
        guard let first = points.first else { return }
        let seedLuminance = stroke.edgeAware ? edgeMap?.luminance(x: stroke.points[0].x, y: stroke.points[0].y) : nil
        let radius = stroke.radius * Double(min(width, height))
        let innerRadius = radius * (1 - stroke.softness)
        let bounds = PixelBounds(points: points, radius: radius, width: width, height: height)
        var coverage = [Float](repeating: 0, count: bounds.columns * bounds.rows)

        func paintSegment(from start: BrushPoint, to end: BrushPoint) throws {
            let dx = end.x - start.x, dy = end.y - start.y
            let lengthSquared = dx * dx + dy * dy
            let segment = PixelBounds(points: [start, end], radius: radius, width: width, height: height)
            for y in segment.y0..<segment.y1 {
                if y.isMultiple(of: 32) { try Task.checkCancellation() }
                let py = Double(y) + 0.5 - start.y
                for x in segment.x0..<segment.x1 {
                    let px = Double(x) + 0.5 - start.x
                    let t = lengthSquared == 0 ? 0 : min(1, max(0, (px * dx + py * dy) / lengthSquared))
                    let vx = px - t * dx, vy = py - t * dy
                    let squaredDistance = vx * vx + vy * vy
                    guard squaredDistance <= radius * radius else { continue }
                    let opacity: Double
                    if squaredDistance <= innerRadius * innerRadius {
                        opacity = 1
                    } else {
                        let t = (radius - sqrt(squaredDistance)) / (radius - innerRadius)
                        opacity = t * t * (3 - 2 * t)
                    }
                    let edgeWeight: Double
                    if let seedLuminance, let edgeMap {
                        let difference = abs(edgeMap.luminance(x: (Double(x) + 0.5) / Double(width),
                                                               y: (Double(y) + 0.5) / Double(height)) - seedLuminance)
                        let position = min(1, max(0, (difference - 0.025) / 0.125))
                        edgeWeight = 1 - position * position * (3 - 2 * position)
                    } else { edgeWeight = 1 }
                    let index = (y - bounds.y0) * bounds.columns + x - bounds.x0
                    coverage[index] = max(coverage[index], Float(opacity * edgeWeight))
                }
            }
        }

        if points.count == 1 { try paintSegment(from: first, to: first) }
        for (start, end) in zip(points, points.dropFirst()) {
            // Subdivide long diagonals to avoid evaluating their entire bounding rectangle.
            let length = hypot(end.x - start.x, end.y - start.y)
            let steps = max(1, Int(ceil(length / max(16, radius * 2))))
            var previous = start
            for step in 1...steps {
                let t = Double(step) / Double(steps)
                let next = BrushPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                try paintSegment(from: previous, to: next)
                previous = next
            }
        }
        let strength = Float(stroke.strength)
        for y in bounds.y0..<bounds.y1 {
            if y.isMultiple(of: 32) { try Task.checkCancellation() }
            for x in bounds.x0..<bounds.x1 {
                let amount = coverage[(y - bounds.y0) * bounds.columns + x - bounds.x0] * strength
                let index = y * width + x
                if stroke.erasing { mask[index] *= 1 - amount }
                else { mask[index] += (1 - mask[index]) * amount }
            }
        }
    }

    private struct PixelBounds {
        let x0: Int, x1: Int, y0: Int, y1: Int
        var columns: Int { x1 - x0 }
        var rows: Int { y1 - y0 }

        init(points: [BrushPoint], radius: Double, width: Int, height: Int) {
            let xs = points.map(\.x), ys = points.map(\.y)
            x0 = max(0, Int(floor((xs.min() ?? 0) - radius)))
            x1 = min(width, Int(ceil((xs.max() ?? 0) + radius)))
            y0 = max(0, Int(floor((ys.min() ?? 0) - radius)))
            y1 = min(height, Int(ceil((ys.max() ?? 0) + radius)))
        }
    }
}

public extension Renderer {
    /// Viewer-only coloured mask overlay. It is never part of the edited export pipeline.
    static func localBrushMaskOverlay(_ url: URL, adjustments: Adjustments,
                                      adjustment: LocalBrushAdjustment,
                                      maxDimension: CGFloat? = nil) throws -> CGImage? {
        try Task.checkCancellation()
        guard adjustments.localBrushes.contains(where: { $0.adjustment == adjustment && !$0.erasing && $0.isValid }),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let sourceWidth = properties?[kCGImagePropertyPixelWidth as String] as? Int ?? 1
        let sourceHeight = properties?[kCGImagePropertyPixelHeight as String] as? Int ?? 1
        let size = maxDimension.map { min(Int($0), max(sourceWidth, sourceHeight)) } ?? max(sourceWidth, sourceHeight)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let sourceContext = CGContext(data: nil, width: decoded.width, height: decoded.height,
                                            bitsPerComponent: 8, bytesPerRow: decoded.width * 4, space: space,
                                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                CGBitmapInfo.byteOrder32Big.rawValue),
              let sourceData = sourceContext.data,
              let overlayContext = CGContext(data: nil, width: decoded.width, height: decoded.height,
                                             bitsPerComponent: 8, bytesPerRow: decoded.width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                CGBitmapInfo.byteOrder32Big.rawValue),
              let overlayData = overlayContext.data else { throw LibraryError.unsupportedImage("brush mask overlay") }
        sourceContext.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let sourcePixels = sourceData.bindMemory(to: UInt8.self, capacity: decoded.width * decoded.height * 4)
        let edgeMap = adjustments.localBrushes.contains(where: \.edgeAware)
            ? LocalBrushEdgeMap(pixels: UnsafePointer(sourcePixels), width: decoded.width, height: decoded.height)
            : nil
        guard let mask = try LocalExposureMask(strokes: adjustments.localBrushes,
            settings: adjustments.localBrushMaskSettings, sourceWidth: decoded.width,
            sourceHeight: decoded.height, edgeMap: edgeMap) else { return nil }
        let overlay = overlayData.bindMemory(to: UInt8.self, capacity: decoded.width * decoded.height * 4)
        let color: (UInt8, UInt8, UInt8) = adjustment == .dodge ? (255, 205, 30) : (45, 115, 255)
        for y in 0..<decoded.height {
            if y.isMultiple(of: 64) { try Task.checkCancellation() }
            for x in 0..<decoded.width {
                let offset = (y * decoded.width + x) * 4
                let alpha = min(190, max(0, Int((mask.coverage(for: adjustment, x: x, y: y,
                    imageWidth: decoded.width, imageHeight: decoded.height) * 190).rounded())))
                overlay[offset] = UInt8(Int(color.0) * alpha / 255)
                overlay[offset + 1] = UInt8(Int(color.1) * alpha / 255)
                overlay[offset + 2] = UInt8(Int(color.2) * alpha / 255)
                overlay[offset + 3] = UInt8(alpha)
            }
        }
        guard let raw = overlayContext.makeImage() else { return nil }
        let lensed = try applyLens(raw, amount: adjustments.lensDistortion)
        return try applyGeometry(lensed, adjustments: adjustments)
    }
}
