import Foundation
import ImageIO

public struct GPSCoordinates: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init?(latitude: Double, longitude: Double) {
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        self.latitude = latitude == 0 ? 0 : latitude
        self.longitude = longitude == 0 ? 0 : longitude
    }

    private enum CodingKeys: String, CodingKey { case latitude, longitude }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let latitude = try values.decode(Double.self, forKey: .latitude)
        let longitude = try values.decode(Double.self, forKey: .longitude)
        guard let coordinates = Self(latitude: latitude, longitude: longitude) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid GPS coordinates"))
        }
        self = coordinates
    }

    init?(properties: [String: Any]) {
        guard let gps = properties[kCGImagePropertyGPSDictionary as String] as? [String: Any],
              let latitude = Self.coordinate(in: gps, value: kCGImagePropertyGPSLatitude,
                                             reference: kCGImagePropertyGPSLatitudeRef,
                                             maximum: 90, positive: "N", negative: "S"),
              let longitude = Self.coordinate(in: gps, value: kCGImagePropertyGPSLongitude,
                                              reference: kCGImagePropertyGPSLongitudeRef,
                                              maximum: 180, positive: "E", negative: "W") else { return nil }
        self.init(latitude: latitude, longitude: longitude)
    }

    private static func coordinate(in gps: [String: Any], value: CFString, reference: CFString,
                                   maximum: Double, positive: String, negative: String) -> Double? {
        guard let number = gps[value as String] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              let hemisphere = (gps[reference as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
              hemisphere == positive || hemisphere == negative else { return nil }
        let degrees = number.doubleValue
        guard degrees.isFinite, abs(degrees) <= maximum else { return nil }
        // EXIF stores magnitudes. Also accept an already-signed value in its stated hemisphere.
        guard degrees >= 0 || hemisphere == negative else { return nil }
        if degrees == 0 { return 0 }
        return hemisphere == negative ? -abs(degrees) : degrees
    }
}

public struct GPSIndex: Codable, Equatable, Sendable {
    public let coordinates: GPSCoordinates?

    init(properties: [String: Any]) {
        coordinates = GPSCoordinates(properties: properties)
    }
}

public struct OriginalPhotoMetadata: Sendable {
    public let exif: CameraEXIF
    public let gps: GPSCoordinates?

    init(properties: [String: Any]) {
        exif = CameraEXIF(properties: properties)
        gps = GPSCoordinates(properties: properties)
    }
}

public extension LibraryRepository {
    func originalMetadata(for photo: Photo) throws -> OriginalPhotoMetadata {
        OriginalPhotoMetadata(properties: try originalImageProperties(for: photo))
    }
}

extension LibraryRepository {
    func originalImageProperties(for photo: Photo) throws -> [String: Any] {
        let url = try availableOriginalURL(photo)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw LibraryError.unsupportedImage(photo.originalName)
        }
        return try Self.primaryImageProperties(in: source, name: photo.originalName)
    }

    static func primaryImageProperties(in source: CGImageSource, name: String) throws -> [String: Any] {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, CGImageSourceGetPrimaryImageIndex(source), nil)
                as? [String: Any] else {
            throw LibraryError.unsupportedImage(name)
        }
        return properties
    }
}
