import Foundation
import ImageIO

public enum PhotoLocationOverride: Codable, Equatable, Sendable {
    case assigned(GPSCoordinates)
    case cleared
}

public extension Photo {
    /// True for an original that has been checked or a version with a location edit.
    var hasCataloguedLocation: Bool { locationOverride != nil || gpsIndex != nil }

    var cataloguedLocation: GPSCoordinates? {
        switch locationOverride {
        case .assigned(let coordinates): return coordinates
        case .cleared: return nil
        case nil: return gpsIndex?.coordinates
        }
    }
}

extension Photo {
    func exportGPSProperties(from originalProperties: [String: Any]) -> [String: Any]? {
        let embedded = originalProperties[kCGImagePropertyGPSDictionary as String] as? [String: Any]
        guard hasCataloguedLocation else { return embedded }
        guard let coordinates = cataloguedLocation else { return nil }
        if locationOverride == nil, GPSCoordinates(properties: originalProperties) == coordinates {
            return embedded
        }
        // A new coordinate pair has no measured altitude, heading or GPS timestamp.
        return [
            kCGImagePropertyGPSLatitude as String: abs(coordinates.latitude),
            kCGImagePropertyGPSLatitudeRef as String: coordinates.latitude < 0 ? "S" : "N",
            kCGImagePropertyGPSLongitude as String: abs(coordinates.longitude),
            kCGImagePropertyGPSLongitudeRef as String: coordinates.longitude < 0 ? "W" : "E"
        ]
    }
}

public struct PhotoLocationChange: Codable, Equatable {
    public let photoID: UUID
    public let location: PhotoLocationOverride?

    public init(photoID: UUID, location: PhotoLocationOverride?) {
        self.photoID = photoID
        self.location = location
    }
}

public extension Library {
    mutating func replaceLocations(_ changes: [PhotoLocationChange]) -> [PhotoLocationChange]? {
        applyPhotoFieldChanges(changes, photoID: \.photoID) { photo, change in
            let previous = PhotoLocationChange(photoID: photo.id, location: photo.locationOverride)
            photo.locationOverride = change.location
            return previous
        }
    }
}
