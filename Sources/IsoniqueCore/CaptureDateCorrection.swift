import Foundation

public struct CaptureDateChange: Codable, Equatable {
    public let photoID: UUID
    public let value: String
}

public struct CaptureDateCorrection: Identifiable {
    public let id = UUID()
    public let referenceName: String?
    public let referenceValue: String?
    public let originalValues: [UUID: String]

    private let photos: [(id: UUID, value: String, date: Date?)]
    private let referenceDate: Date?

    public init(photos: [Photo], preferredReferenceID: UUID?) {
        let dated = photos.map { ($0.id, $0.captureDate, Self.parse($0.captureDate)) }
        let reference = dated.first { $0.0 == preferredReferenceID && $0.2 != nil }
            ?? dated.first { $0.2 != nil }
        referenceDate = reference?.2
        referenceValue = reference?.1
        referenceName = photos.first { $0.id == reference?.0 }?.displayName
        originalValues = Dictionary(uniqueKeysWithValues: dated.map { ($0.0, $0.1) })
        // Put the reference first so Undo can return to it when it changed.
        self.photos = dated.filter { $0.0 == reference?.0 } + dated.filter { $0.0 != reference?.0 }
    }

    public struct Preview {
        public let changes: [CaptureDateChange]
        public let skipped: Int
    }

    public enum InvalidDate: LocalizedError {
        case input, reference, range

        public var errorDescription: String? {
            switch self {
            case .input: return "Enter a valid date and time in YYYY:MM:DD HH:mm:ss format."
            case .reference: return "Keeping intervals requires a photo with a known capture time."
            case .range: return "This shift would put a capture date outside the supported calendar range."
            }
        }
    }

    public func preview(_ value: String, preservingIntervals: Bool) throws -> Preview {
        let adjusted = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = Self.parse(adjusted) else { throw InvalidDate.input }
        let shift: TimeInterval?
        if preservingIntervals {
            guard let referenceDate else { throw InvalidDate.reference }
            shift = date.timeIntervalSince(referenceDate)
        } else {
            shift = nil
        }

        var changes: [CaptureDateChange] = []
        var skipped = 0
        for photo in photos {
            let newValue: String
            if let shift {
                guard let originalDate = photo.date else { skipped += 1; continue }
                let shifted = originalDate.addingTimeInterval(shift)
                newValue = Self.formatter.string(from: shifted)
                guard Self.parse(newValue) == shifted else { throw InvalidDate.range }
            } else {
                newValue = adjusted
            }
            if newValue != photo.value { changes.append(CaptureDateChange(photoID: photo.id, value: newValue)) }
        }
        return Preview(changes: changes, skipped: skipped)
    }

    static func parse(_ value: String) -> Date? {
        guard value.utf8.count == 19, let date = formatter.date(from: value),
              formatter.string(from: date) == value else { return nil }
        return date
    }

    // EXIF stores a camera wall-clock value. A fixed offset keeps shifts independent of the Mac's time zone and DST.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        formatter.isLenient = false
        return formatter
    }()
}

public extension Library {
    /// Apply a complete set of date changes and return the previous values for Undo.
    mutating func replaceCaptureDates(_ changes: [CaptureDateChange]) -> [CaptureDateChange]? {
        applyPhotoFieldChanges(changes, photoID: \.photoID) { photo, change in
            let previous = CaptureDateChange(photoID: photo.id, value: photo.captureDate)
            photo.captureDate = change.value
            return previous
        }
    }
}
