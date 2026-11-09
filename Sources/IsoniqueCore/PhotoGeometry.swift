import Foundation
import CoreGraphics

/// Geometry in top-left pixel-edge coordinates, after ImageIO has applied EXIF orientation.
public struct PhotoGeometry: Equatable {
    public let sourceSize: CGSize
    let turns: Int
    let angle: CGFloat
    let rotatedSize: CGSize
    let straightenedSize: CGSize
    let flipHorizontal: Bool
    let flipVertical: Bool
    let cropRect: CGRect?
    let lensAmount: Double

    init(width: Int, height: Int, adjustments: Adjustments) {
        sourceSize = CGSize(width: width, height: height)
        turns = ((adjustments.quarterTurns % 4) + 4) % 4
        rotatedSize = turns.isMultiple(of: 2) ? sourceSize : CGSize(width: height, height: width)
        angle = StraightenRules.clamp(adjustments.straighten) * .pi / 180
        let w = rotatedSize.width, h = rotatedSize.height
        let cosine = abs(cos(angle)), sine = abs(sin(angle))
        let factor = min(w / (w * cosine + h * sine), h / (w * sine + h * cosine))
        straightenedSize = angle == 0 ? rotatedSize : CGSize(width: max(1, floor(w * factor)), height: max(1, floor(h * factor)))
        flipHorizontal = adjustments.flipHorizontal
        flipVertical = adjustments.flipVertical
        lensAmount = adjustments.lensDistortion.isFinite ? adjustments.lensDistortion : 0
        if let crop = adjustments.crop, [crop.x, crop.y, crop.width, crop.height].allSatisfy(\.isFinite),
           crop.width > 0, crop.height > 0 {
            let size = straightenedSize
            let aligned = CGRect(x: (crop.x * size.width).rounded(), y: (crop.y * size.height).rounded(),
                                 width: (crop.width * size.width).rounded(), height: (crop.height * size.height).rounded())
            let clipped = aligned.intersection(CGRect(origin: .zero, size: size))
            cropRect = clipped.width >= 1 && clipped.height >= 1 ? clipped : nil
        } else {
            cropRect = nil
        }
    }

    public func matches(_ adjustments: Adjustments) -> Bool {
        self == PhotoGeometry(width: Int(sourceSize.width), height: Int(sourceSize.height), adjustments: adjustments)
    }

    /// Map a normalized point in the displayed image back to the source brush coordinate system.
    public func sourcePoint(x: Double, y: Double) -> BrushPoint {
        let rect = cropRect ?? CGRect(origin: .zero, size: straightenedSize)
        var x = rect.minX + x * rect.width
        var y = rect.minY + y * rect.height
        if flipHorizontal { x = straightenedSize.width - x }
        if flipVertical { y = straightenedSize.height - y }
        if angle != 0 {
            let dx = x - straightenedSize.width / 2, dy = y - straightenedSize.height / 2
            x = rotatedSize.width / 2 + cos(angle) * dx + sin(angle) * dy
            y = rotatedSize.height / 2 - sin(angle) * dx + cos(angle) * dy
        }
        switch turns {
        case 1: (x, y) = (y, sourceSize.height - x)
        case 2: (x, y) = (sourceSize.width - x, sourceSize.height - y)
        case 3: (x, y) = (sourceSize.width - y, x)
        default: break
        }
        x /= sourceSize.width
        y /= sourceSize.height
        if lensAmount != 0 {
            let point = Self.lensSourcePoint(x: x, y: y, coefficient: min(1, max(-1, lensAmount)) * 0.35)
            (x, y) = (point.x, point.y)
        }
        return BrushPoint(x: min(1, max(0, x)), y: min(1, max(0, y)))
    }

    static func lensSourcePoint(x: Double, y: Double, coefficient: Double) -> CGPoint {
        let nx = x * 2 - 1, ny = y * 2 - 1
        let factor = 1 + coefficient * (nx * nx + ny * ny)
        return CGPoint(x: (nx * factor + 1) / 2, y: (ny * factor + 1) / 2)
    }
}
