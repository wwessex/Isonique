import Foundation

public struct GPXTrack: Sendable {
    public enum ReadError: LocalizedError {
        case invalidTrack, noTimedPoints

        public var errorDescription: String? {
            switch self {
            case .invalidTrack: return "The file is not a readable GPX track."
            case .noTimedPoints: return "The GPX file has no track points with valid coordinates and timestamps."
            }
        }
    }

    public struct Match: Equatable, Sendable {
        public enum Method: Sendable { case exact, interpolated }

        public let coordinates: GPSCoordinates
        public let method: Method
    }

    fileprivate struct Point: Sendable {
        let time: Date
        let coordinates: GPSCoordinates
    }

    private let segments: [[Point]]

    public init(contentsOf url: URL) throws {
        try Task.checkCancellation()
        guard let stream = InputStream(url: url) else { throw ReadError.invalidTrack }
        try self.init(parser: XMLParser(stream: stream))
    }

    public init(data: Data) throws {
        try self.init(parser: XMLParser(data: data))
    }

    private init(parser: XMLParser) throws {
        try Task.checkCancellation()
        let reader = GPXTrackReader()
        parser.delegate = reader
        parser.shouldProcessNamespaces = true
        parser.externalEntityResolvingPolicy = .never
        let parsed = parser.parse()
        try Task.checkCancellation()
        guard parsed, reader.hasGPXRoot else { throw ReadError.invalidTrack }
        guard !reader.segments.isEmpty else { throw ReadError.noTimedPoints }
        segments = reader.segments
    }

    /// Match only within a continuous segment. Overlapping tracks must agree, with exact fixes taking precedence.
    public func match(at time: Date, maximumGap: TimeInterval) -> Match? {
        var exact: GPSCoordinates?
        var interpolated: GPSCoordinates?
        var ambiguousInterpolation = false
        for segment in segments {
            guard time >= segment[0].time, time <= segment[segment.count - 1].time else { continue }
            var lower = 0
            var upper = segment.count - 1
            while lower < upper {
                let mid = lower + (upper - lower) / 2
                if segment[mid].time < time { lower = mid + 1 }
                else { upper = mid }
            }
            let after = segment[lower]
            if after.time == time {
                if let exact, exact != after.coordinates { return nil }
                exact = after.coordinates
            } else if lower > 0 {
                let before = segment[lower - 1]
                let gap = after.time.timeIntervalSince(before.time)
                guard gap <= maximumGap else { continue }
                let fraction = time.timeIntervalSince(before.time) / gap
                if let point = Self.interpolate(from: before.coordinates, to: after.coordinates, fraction: fraction) {
                    if let interpolated, interpolated != point { ambiguousInterpolation = true }
                    interpolated = point
                }
            }
        }
        if let exact { return Match(coordinates: exact, method: .exact) }
        guard let interpolated, !ambiguousInterpolation else { return nil }
        return Match(coordinates: interpolated, method: .interpolated)
    }

    private static func interpolate(from start: GPSCoordinates, to end: GPSCoordinates,
                                    fraction: Double) -> GPSCoordinates? {
        let latitude = start.latitude + (end.latitude - start.latitude) * fraction
        var longitudeDelta = end.longitude - start.longitude
        if longitudeDelta > 180 { longitudeDelta -= 360 }
        if longitudeDelta < -180 { longitudeDelta += 360 }
        var longitude = start.longitude + longitudeDelta * fraction
        if longitude > 180 { longitude -= 360 }
        if longitude < -180 { longitude += 360 }
        return GPSCoordinates(latitude: latitude, longitude: longitude)
    }
}

private final class GPXTrackReader: NSObject, XMLParserDelegate {
    private enum Element { case root, track, segment, point, time, ignored }

    private var path: [Element] = []
    private var namespace = ""
    private var coordinates: GPSCoordinates?
    private var timeText = ""
    private var pointTime: Date?
    private var segment: [GPXTrack.Point] = []
    private(set) var hasGPXRoot = false
    private(set) var segments: [[GPXTrack.Point]] = []

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String]) {
        guard !Task.isCancelled else { parser.abortParsing(); return }
        let uri = namespaceURI ?? ""
        let parent = path.last
        let element: Element
        switch (parent, name) {
        case (nil, "gpx") where ["", "http://www.topografix.com/GPX/1/0", "http://www.topografix.com/GPX/1/1"].contains(uri):
            namespace = uri
            hasGPXRoot = true
            element = .root
        case (.root, "trk") where uri == namespace: element = .track
        case (.track, "trkseg") where uri == namespace: element = .segment
        case (.segment, "trkpt") where uri == namespace:
            coordinates = Self.coordinates(attributes)
            pointTime = nil
            element = .point
        case (.point, "time") where uri == namespace:
            timeText = ""
            element = .time
        default: element = .ignored
        }
        path.append(element)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if path.last == .time { timeText += string }
    }

    func parser(_ parser: XMLParser, foundCDATA data: Data) {
        if path.last == .time, let string = String(data: data, encoding: .utf8) { timeText += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        switch path.popLast() {
        case .time:
            pointTime = Self.timestamp(timeText)
        case .point:
            guard let coordinates, let pointTime else { finishSegment(); return }
            if let last = segment.last, last.time >= pointTime {
                if last.time == pointTime, last.coordinates == coordinates { return }
                finishSegment()
            }
            segment.append(.init(time: pointTime, coordinates: coordinates))
        case .segment:
            finishSegment()
        default: break
        }
    }

    private func finishSegment() {
        guard !segment.isEmpty else { return }
        segments.append(segment)
        segment = []
    }

    private static func coordinates(_ attributes: [String: String]) -> GPSCoordinates? {
        guard let latitude = attributes["lat"].flatMap(Double.init),
              let longitude = attributes["lon"].flatMap(Double.init) else { return nil }
        return GPSCoordinates(latitude: latitude, longitude: longitude)
    }

    private static func timestamp(_ text: String) -> Date? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = timestampPattern.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
              match.range.length == value.utf16.count else { return nil }
        let fractional = value.contains(".")
        let style = Date.ISO8601FormatStyle(includingFractionalSeconds: fractional)
        guard let date = try? style.parse(value),
              CaptureDateCorrection.parse(value.prefix(19).replacingOccurrences(of: "-", with: ":")
                  .replacingOccurrences(of: "T", with: " ")) != nil else { return nil }
        return date
    }

    // Require an explicit UTC designator or offset so track times are independent of the Mac.
    private static let timestampPattern = try! NSRegularExpression(
        pattern: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]+)?(Z|[+-](0[0-9]|1[0-4]):[0-5][0-9])$"#
    )
}
