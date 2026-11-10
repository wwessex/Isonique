import Foundation
import ImageIO

public struct CameraEXIF: Codable, Equatable, Sendable {
    public let exposureSeconds: Double?
    public let fNumber: Double?
    public let iso: Int?
    public let focalLengthMM: Double?
    public let lens: String?

    public var isEmpty: Bool {
        exposureSeconds == nil && fNumber == nil && iso == nil && focalLengthMM == nil && lens == nil
    }

    init(properties: [String: Any]) {
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let auxiliary = properties[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]
        exposureSeconds = Self.positive(Self.number(exif[kCGImagePropertyExifExposureTime as String]))
            ?? Self.positive(Self.number(exif[kCGImagePropertyExifShutterSpeedValue as String]).map { pow(2, -$0) })
        fNumber = Self.positive(Self.number(exif[kCGImagePropertyExifFNumber as String]))
            ?? Self.positive(Self.number(exif[kCGImagePropertyExifApertureValue as String]).map { pow(2, $0 / 2) })
        let ratings = exif[kCGImagePropertyExifISOSpeedRatings as String]
        let isoFallbacks = [
            kCGImagePropertyExifISOSpeed, kCGImagePropertyExifRecommendedExposureIndex,
            kCGImagePropertyExifStandardOutputSensitivity
        ].compactMap { exif[$0 as String] }
        let isoValues = (ratings as? [Any] ?? ratings.map { [$0] } ?? []) + isoFallbacks
        iso = isoValues.lazy.compactMap { Self.positive(Self.number($0)).flatMap { Int(exactly: $0) } }.first
        focalLengthMM = Self.positive(Self.number(exif[kCGImagePropertyExifFocalLength as String]))
        lens = Self.name(exif[kCGImagePropertyExifLensModel as String])
            ?? Self.name(auxiliary[kCGImagePropertyExifAuxLensModel as String])
    }

    private static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite else { return nil }
        return value.doubleValue
    }

    private static func positive(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value > 0 else { return nil }
        return value
    }

    private static func name(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return nil }
        return text
    }
}

public extension LibraryRepository {
    func cameraEXIF(for photo: Photo) throws -> CameraEXIF {
        let url = try availableOriginalURL(photo)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw LibraryError.unsupportedImage(photo.originalName)
        }
        return try Self.cameraEXIF(in: source, name: photo.originalName)
    }

    internal static func cameraEXIF(in source: CGImageSource, name: String) throws -> CameraEXIF {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil)
                as? [String: Any] else {
            throw LibraryError.unsupportedImage(name)
        }
        return CameraEXIF(properties: properties)
    }
}
