import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum ExportFormat: String, Codable, CaseIterable, Identifiable {
    case jpeg = "JPEG", png = "PNG", tiff = "TIFF", heif = "HEIF", original = "Original file"
    public var id: String { rawValue }
    public var type: UTType {
        switch self {
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        case .heif: return .heic
        case .original: return .data
        }
    }
    public var suffix: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .heif: return "heic"
        case .original: return ""
        }
    }
    var fileExtensions: [String] {
        switch self {
        case .jpeg: return ["jpg", "jpeg"]
        case .png: return ["png"]
        case .tiff: return ["tif", "tiff"]
        case .heif: return ["heic", "heif"]
        case .original: return []
        }
    }
}
public enum TIFFCompression: String, Codable, CaseIterable, Identifiable {
    case uncompressed = "None"
    case lzw = "LZW"
    case zip = "ZIP"
    case packBits = "PackBits"

    public var id: String { rawValue }

    var imageIOValue: Int {
        switch self {
        case .uncompressed: return 1
        case .lzw: return 5
        case .zip: return 8
        case .packBits: return 32773
        }
    }
}
public enum WatermarkPosition: String, Codable, CaseIterable, Identifiable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case center = "Center"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"

    public var id: String { rawValue }
}
public struct WatermarkSettings: Codable, Equatable, Hashable {
    public var text: String
    public var position: WatermarkPosition
    public var opacity: Double
    /// Font height as a fraction of the image's shorter edge.
    public var scale: Double

    public init(text: String, position: WatermarkPosition = .bottomRight,
                opacity: Double = 0.75, scale: Double = 0.06) {
        self.text = text
        self.position = position
        self.opacity = opacity
        self.scale = scale
    }
}
public struct ExportOptions: Codable, Equatable {
    public var format: ExportFormat = .jpeg
    public var quality = 0.95
    /// Zero keeps the full size. Smaller images are never enlarged.
    public var maxDimension = 0
    public var exif = false
    public var iptc = false
    public var gps = false
    /// Optional so existing saved export presets still decode.
    public var xmpSidecar: Bool?
    /// An absent template keeps the default numbered version names for batch export.
    public var filenameTemplate: String?
    /// Older presets omit this field and retain the exporter's uncompressed TIFF behavior.
    public var tiffCompression: TIFFCompression?
    /// Absent in older presets and when watermarking is disabled.
    public var watermark: WatermarkSettings?
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
    case iptcTitle = "IPTC Title", iptcCreator = "IPTC Creator"
    case iptcCopyright = "IPTC Copyright", iptcCredit = "IPTC Credit"
    public var id: String { rawValue }

    public var iptcField: IPTCField? {
        switch self {
        case .iptcTitle: return .title
        case .iptcCreator: return .creator
        case .iptcCopyright: return .copyright
        case .iptcCredit: return .credit
        default: return nil
        }
    }
}
public struct LiftedSettings {
    public let source: Photo
    public init(_ photo: Photo, embeddedIPTC: IPTCMetadata = IPTCMetadata()) {
        var snapshot = photo
        let iptc = photo.iptc?.overriding(embeddedIPTC) ?? embeddedIPTC
        snapshot.iptc = iptc.isEmpty ? nil : iptc
        source = snapshot
    }

    public func includesMetadata(_ field: StampMetadata) -> Bool {
        guard let iptcField = field.iptcField else { return true }
        return source.iptc?[iptcField] != nil
    }

    public func applying(to target: Photo, groups: Set<AdjustmentGroup>, metadata: Set<StampMetadata>) -> Photo {
        var result = target
        result.adjustments = source.adjustments.stamping(onto: target.adjustments, groups: groups)
        if metadata.contains(.caption) { result.caption = source.caption }
        if metadata.contains(.keywords) {
            result.keywords = source.keywords
            result.keywordPaths = source.keywordPaths
        }
        if metadata.contains(.rating) { result.rating = RatingRules.clamp(source.rating) }
        let iptc = metadata.compactMap { option -> IPTCFieldEdit? in
            guard let field = option.iptcField, let values = source.iptc?[field] else { return nil }
            return IPTCFieldEdit(field: field, values: values)
        }
        if !iptc.isEmpty { result.applyIPTC(iptc) }
        return result
    }
}
public enum CropRules {
    /// Use absolute field values and invert the ratio after a quarter turn.
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
