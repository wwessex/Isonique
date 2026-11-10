import Foundation

public struct GPSRadiusRule: Codable, Equatable {
    public var latitude: String
    public var longitude: String
    public var kilometres: String

    public init(latitude: String = "", longitude: String = "", kilometres: String = "") {
        self.latitude = latitude
        self.longitude = longitude
        self.kilometres = kilometres
    }

    public var isValid: Bool { region != nil }

    private var region: (centre: GPSCoordinates, radius: Double)? {
        guard let latitude = Self.decimal(latitude, allowingDegrees: true),
              let longitude = Self.decimal(longitude, allowingDegrees: true),
              let centre = GPSCoordinates(latitude: latitude, longitude: longitude),
              let radius = Self.decimal(kilometres), radius > 0 else { return nil }
        return (centre, radius)
    }

    func includes(_ point: GPSCoordinates) -> Bool {
        guard let region else { return false }
        let radians = Double.pi / 180
        let latitudeHalfDelta = (point.latitude - region.centre.latitude) * radians / 2
        let longitudeHalfDelta = (point.longitude - region.centre.longitude) * radians / 2
        // Haversine distance follows the shorter arc across the date line.
        let haversine = pow(sin(latitudeHalfDelta), 2) + cos(point.latitude * radians)
            * cos(region.centre.latitude * radians) * pow(sin(longitudeHalfDelta), 2)
        let distance = 2 * 6371.0088 * asin(sqrt(min(1, max(0, haversine))))
        return distance <= region.radius
    }

    static func decimal(_ input: String, allowingDegrees: Bool = false) -> Double? {
        var number = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if allowingDegrees, number.hasSuffix("°") {
            number.removeLast()
            number = number.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        number = number.replacingOccurrences(of: ",", with: ".").replacingOccurrences(of: "−", with: "-")
        let unsigned = number.dropFirst(number.hasPrefix("-") || number.hasPrefix("+") ? 1 : 0)
        guard unsigned.allSatisfy({ "0123456789.".contains($0) }),
              let value = Double(number), value.isFinite else { return nil }
        return value
    }
}
