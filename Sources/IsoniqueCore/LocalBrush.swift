import Foundation

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
    public let points: [BrushPoint]

    /// Radius is a fraction of the shorter side of the uncropped original.
    public init(adjustment: LocalBrushAdjustment, erasing: Bool = false, radius: Double,
                softness: Double, strength: Double, points: [BrushPoint]) {
        self.adjustment = adjustment
        self.erasing = erasing
        self.radius = radius
        self.softness = softness
        self.strength = strength
        self.points = points
    }

    public var isValid: Bool {
        (0.0025...0.25).contains(radius) && (0...1).contains(softness) &&
            (0...1).contains(strength) && strength > 0 && !points.isEmpty &&
            points.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) }
    }
}

/// Bounded mask raster in source space. Each stroke uses maximum coverage along its
/// path, then composites once, so input sampling frequency does not change opacity.
struct LocalExposureMask {
    let width: Int
    let height: Int
    private var values: [Float]

    init?(strokes: [LocalBrushStroke], sourceWidth: Int, sourceHeight: Int) throws {
        guard strokes.contains(where: { !$0.erasing && $0.isValid }) else { return nil }
        let scale = min(1, 2048 / Double(max(sourceWidth, sourceHeight)))
        width = max(1, Int((Double(sourceWidth) * scale).rounded()))
        height = max(1, Int((Double(sourceHeight) * scale).rounded()))
        var dodge = [Float](repeating: 0, count: width * height)
        var burn = dodge
        for stroke in strokes where stroke.isValid {
            try Task.checkCancellation()
            switch stroke.adjustment {
            case .dodge: try Self.paint(stroke, width: width, height: height, into: &dodge)
            case .burn: try Self.paint(stroke, width: width, height: height, into: &burn)
            }
        }
        for index in dodge.indices { dodge[index] = (dodge[index] - burn[index]) * 1.5 }
        values = dodge
    }

    func exposure(x: Int, y: Int, imageWidth: Int, imageHeight: Int) -> Double {
        if width == imageWidth && height == imageHeight {
            return Double(values[y * width + x])
        }
        let mx = min(Double(width - 1), max(0, (Double(x) + 0.5) * Double(width) / Double(imageWidth) - 0.5))
        let my = min(Double(height - 1), max(0, (Double(y) + 0.5) * Double(height) / Double(imageHeight) - 0.5))
        let x0 = Int(mx), y0 = Int(my)
        let x1 = min(width - 1, x0 + 1), y1 = min(height - 1, y0 + 1)
        let fx = Float(mx - Double(x0)), fy = Float(my - Double(y0))
        let top = values[y0 * width + x0] * (1 - fx) + values[y0 * width + x1] * fx
        let bottom = values[y1 * width + x0] * (1 - fx) + values[y1 * width + x1] * fx
        return Double(top * (1 - fy) + bottom * fy)
    }

    private static func paint(_ stroke: LocalBrushStroke, width: Int, height: Int, into mask: inout [Float]) throws {
        let points = stroke.points.map { BrushPoint(x: $0.x * Double(width), y: $0.y * Double(height)) }
        guard let first = points.first else { return }
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
                    let index = (y - bounds.y0) * bounds.columns + x - bounds.x0
                    coverage[index] = max(coverage[index], Float(opacity))
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
