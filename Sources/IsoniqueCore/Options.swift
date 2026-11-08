import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case jpeg = "JPEG", png = "PNG", tiff = "TIFF", original = "Original file"
    public var id: String { rawValue }
    public var type: UTType { switch self { case .jpeg: return .jpeg; case .png: return .png; case .tiff: return .tiff; case .original: return .data } }
    public var suffix: String { switch self { case .jpeg: return "jpg"; case .png: return "png"; case .tiff: return "tiff"; case .original: return "" } }
}
public struct ExportOptions: Codable, Equatable {
    public var format: ExportFormat = .jpeg
    public var quality = 0.95
    /// Zero keeps the full size. Smaller images are never enlarged.
    public var maxDimension = 0
    public var exif = false
    public var iptc = false
    public var gps = false
    public init() {}
}
public struct ExportPreset: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var options: ExportOptions
    public init(name: String, options: ExportOptions) { self.name = name; self.options = options }
}
public enum StampMetadata: String, CaseIterable, Identifiable {
    case caption = "Caption", keywords = "Keywords", rating = "Rating"
    public var id: String { rawValue }
}
public struct LiftedSettings {
    public let source: Photo
    public init(_ photo: Photo) { source = photo }
    public func applying(to target: Photo, groups: Set<AdjustmentGroup>, metadata: Set<StampMetadata>) -> Photo {
        var result = target
        result.adjustments = source.adjustments.stamping(onto: target.adjustments, groups: groups)
        if metadata.contains(.caption) { result.caption = source.caption }
        if metadata.contains(.keywords) { result.keywords = source.keywords }
        if metadata.contains(.rating) { result.rating = RatingRules.clamp(source.rating) }
        return result
    }
}
public enum CropRules {
    /// Aperture RKCropToolController 0x1001e709b: absolute field values,
    /// with the ratio inverted for source rotations of 90 or 270 degrees.
    public static func aspectRatio(width: Double, height: Double, rotation: Int = 0) -> Double? {
        // Reject invalid input here; the original division has no such guard.
        guard width.isFinite, height.isFinite, width != 0, height != 0 else { return nil }
        let ratio = rotation == 90 || rotation == 270 ? abs(height) / abs(width) : abs(width) / abs(height)
        return ratio.isFinite && ratio > 0 ? ratio : nil
    }
    public static func fitted(x: Double, y: Double, width: Double, height: Double, image: CGSize, aspect: Double? = nil) -> PhotoCrop {
        var w = max(1 / max(1, image.width), min(1, width.isFinite ? width : 1))
        var h = max(1 / max(1, image.height), min(1, height.isFinite ? height : 1))
        if let aspect, aspect.isFinite, aspect > 0 {
            let normalized = aspect * image.height / image.width
            h = w / normalized
            if h > 1 { h = 1; w = normalized }
        }
        return PhotoCrop(x: min(1 - w, max(0, x.isFinite ? x : 0)), y: min(1 - h, max(0, y.isFinite ? y : 0)), width: w, height: h)
    }
    public static func pixels(width: Int, height: Int, image: CGSize, current: PhotoCrop) -> PhotoCrop {
        fitted(x: current.x, y: current.y, width: Double(width) / image.width, height: Double(height) / image.height, image: image)
    }
}
