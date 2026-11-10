import IsoniqueCore
import MapKit

enum GPXTrackPolyline {
    static func overlays(for track: ProjectGPXTrack) -> [MKPolyline] {
        track.segments.flatMap(overlays)
    }

    private static func overlays(for segment: [GPSCoordinates]) -> [MKPolyline] {
        guard let first = segment.first else { return [] }
        var previous = first
        var path = [mapPoint(first)]
        var overlays: [MKPolyline] = []
        for point in segment.dropFirst() {
            let longitudeDelta = point.longitude - previous.longitude
            if abs(longitudeDelta) > 180 {
                // End at one edge of the map and resume at the other edge.
                let edge = longitudeDelta < 0 ? 180.0 : -180.0
                let travel = longitudeDelta + 2 * edge
                let fraction = travel == 0 ? 0 : (edge - previous.longitude) / travel
                let latitude = previous.latitude + fraction * (point.latitude - previous.latitude)
                let edgePoint = MKMapPoint(.init(latitude: latitude, longitude: edge))
                append(edgePoint, to: &path)
                if path.count > 1 { overlays.append(MKPolyline(points: path, count: path.count)) }
                path = [MKMapPoint(.init(latitude: latitude, longitude: -edge))]
            }
            append(mapPoint(point), to: &path)
            previous = point
        }
        if path.count > 1 { overlays.append(MKPolyline(points: path, count: path.count)) }
        return overlays
    }

    private static func append(_ point: MKMapPoint, to path: inout [MKMapPoint]) {
        if let last = path.last, last.x == point.x, last.y == point.y { return }
        path.append(point)
    }

    private static func mapPoint(_ point: GPSCoordinates) -> MKMapPoint {
        MKMapPoint(.init(latitude: point.latitude, longitude: point.longitude))
    }
}
