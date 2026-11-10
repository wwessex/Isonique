import Foundation

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
