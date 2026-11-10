import AppKit
import IsoniqueCore
import MapKit
import SwiftUI

struct PhotoPlace: Identifiable {
    let id: GPSCoordinates
    let photos: [Photo]

    var title: String {
        if photos.count == 1, let photo = photos.first { return photo.displayName }
        return String(localized: "\(photos.count) photos at this location")
    }

    static func grouped(_ photos: [Photo]) -> [Self] {
        var groups: [GPSCoordinates: [Photo]] = [:]
        var order: [GPSCoordinates] = []
        for photo in photos {
            guard let point = photo.cataloguedLocation else { continue }
            if groups[point] == nil { order.append(point) }
            groups[point, default: []].append(photo)
        }
        return order.compactMap { point in groups[point].map { Self(id: point, photos: $0) } }
    }
}

extension Workspace {
    func selectPlace(_ point: GPSCoordinates) {
        guard !busy, presentation == .places, selected?.cataloguedLocation != point,
              let photo = photos.first(where: { $0.cataloguedLocation == point }) else { return }
        selectBrowserPhoto(photo.id)
    }
}

struct PlacesBrowser<PhotoCell: View>: View {
    @ObservedObject var model: Workspace
    @ViewBuilder var photoCell: (Photo, @escaping () -> Void) -> PhotoCell

    @State private var framing = PlacesMap.Framing()

    var body: some View {
        let photos = model.photos
        let places = PhotoPlace.grouped(photos)
        let project = model.placesProject
        let tracks = model.visibleGPXTracks
        let hasMapContent = !places.isEmpty || !tracks.isEmpty
        VStack(spacing: 0) {
            if hasMapContent || project != nil {
                HStack(spacing: 12) {
                    if !places.isEmpty {
                        Text(places.count == 1 ? "1 location" : "\(places.count) locations")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !tracks.isEmpty {
                        Text(tracks.count == 1 ? "1 visible GPX track" : "\(tracks.count) visible GPX tracks")
                        .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let project {
                        ProjectGPXTracksMenu(model: model, project: project).id(project.id)
                    }
                    if hasMapContent {
                        Button(tracks.isEmpty ? "Fit Locations" : "Fit Map", systemImage: "arrow.up.left.and.arrow.down.right") {
                            framing = PlacesMap.Framing()
                        }
                    }
                    if !places.isEmpty {
                        Button("Open Selected Photo", systemImage: "rectangle.bottomthird.inset.filled") {
                            model.choosePresentation(.viewer)
                        }.disabled(model.selected == nil)
                    }
                }.padding(.horizontal, 14).padding(.vertical, 8)
            }
            if hasMapContent {
                PlacesMap(places: places, tracks: tracks, scope: model.scope, selected: model.selected?.cataloguedLocation,
                          framing: framing, onSelect: model.selectPlace) { trackID, waypointID in
                    model.openGPXWaypointAssignment(trackID: trackID, waypointID: waypointID)
                }
                if !photos.isEmpty { filmstrip(photos) }
            } else {
                ContentUnavailableView {
                    Label("No catalogued locations in this view", systemImage: "map")
                } description: {
                    if project?.gpxTracks?.isEmpty == false {
                        Text("Show a track from the GPX Tracks menu.")
                    } else if project != nil {
                        Text("Import a GPX file from the GPX Tracks menu, or catalogue GPS from photos in Grid or List.")
                    } else {
                        Text("Choose Grid or List to select older photos, then choose Metadata → Catalogue GPS from Originals.")
                    }
                }
            }
        }
    }

    private func filmstrip(_ photos: [Photo]) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(photos) { photo in
                        photoCell(photo) {
                            model.selectBrowserPhoto(photo.id)
                            framing = PlacesMap.Framing(centre: photo.cataloguedLocation)
                        }.id(photo.id)
                    }
                }.padding(10)
            }
            .scrollIndicators(.hidden)
            .frame(height: 112)
            .accessibilityLabel("Photos with catalogued locations")
            .onChange(of: model.selection, initial: true) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

}

struct PlacesMap: NSViewRepresentable {
    struct Framing: Equatable {
        var centre: GPSCoordinates?
        private let id = UUID()
    }

    let places: [PhotoPlace]
    let tracks: [ProjectGPXTrack]
    let scope: String
    let selected: GPSCoordinates?
    let framing: Framing
    let onSelect: (GPSCoordinates) -> Void
    let onSelectWaypoint: (UUID, UUID) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PhotoMapView {
        let map = PhotoMapView(accessibilityLabel: String(localized: "Photo locations map"))
        map.delegate = context.coordinator
        return map
    }

    func updateNSView(_ map: PhotoMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onSelect = onSelect
        coordinator.onSelectWaypoint = onSelectWaypoint
        coordinator.selected = selected
        let scopeChanged = coordinator.scope != scope
        let tracksChanged = coordinator.updateTrackOverlays(tracks, on: map, replacing: scopeChanged)

        let previous = Set(coordinator.pins.keys)
        let points = Set(places.map(\.id))
        for point in previous.subtracting(points) {
            if let pin = coordinator.pins.removeValue(forKey: point) { map.removeAnnotation(pin) }
        }
        for place in places {
            if let pin = coordinator.pins[place.id] {
                if pin.title != place.title { pin.title = place.title }
            } else {
                let pin = Pin(place: place)
                coordinator.pins[place.id] = pin
                map.addAnnotation(pin)
            }
        }

        if let selected, let pin = coordinator.pins[selected], !map.selectedAnnotations.contains(where: { $0 === pin }) {
            map.selectAnnotation(pin, animated: false)
        }

        let contentChanged = scopeChanged || previous != points || tracksChanged
        if contentChanged || coordinator.framing != framing {
            if !contentChanged, let centre = framing.centre {
                map.fit(PhotoMapFraming.bounds(for: [centre]))
            } else {
                var boundsPoints = points
                for track in tracks {
                    boundsPoints.formUnion(track.segments.joined())
                    boundsPoints.formUnion((track.waypoints ?? []).lazy.map(\.coordinates))
                }
                map.fit(PhotoMapFraming.bounds(for: boundsPoints))
            }
        }
        coordinator.scope = scope
        coordinator.framing = framing
    }

    final class Pin: MKPointAnnotation {
        let point: GPSCoordinates

        init(place: PhotoPlace) {
            point = place.id
            super.init()
            coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            title = place.title
        }
    }

    final class WaypointPin: MKPointAnnotation {
        let trackID: UUID
        let waypointID: UUID

        init(trackID: UUID, waypoint: GPXWaypoint) {
            self.trackID = trackID
            waypointID = waypoint.id
            super.init()
            coordinate = CLLocationCoordinate2D(latitude: waypoint.coordinates.latitude, longitude: waypoint.coordinates.longitude)
            title = waypoint.displayName
        }
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var pins: [GPSCoordinates: Pin] = [:]
        var selected: GPSCoordinates?
        var framing: Framing?
        var scope: String?
        var onSelect: ((GPSCoordinates) -> Void)?
        var onSelectWaypoint: ((UUID, UUID) -> Void)?
        private var trackContent: [UUID: (overlays: [MKPolyline], waypoints: [WaypointPin])] = [:]

        @discardableResult
        func updateTrackOverlays(_ tracks: [ProjectGPXTrack], on map: MKMapView, replacing: Bool = false) -> Bool {
            let current = Set(trackContent.keys)
            let incoming = Set(tracks.map(\.id))
            guard replacing || current != incoming else { return false }
            let removed = replacing ? current : current.subtracting(incoming)
            for id in removed {
                if let content = trackContent.removeValue(forKey: id) {
                    map.removeOverlays(content.overlays)
                    map.removeAnnotations(content.waypoints)
                }
            }
            for track in tracks where trackContent[track.id] == nil {
                let overlays = GPXTrackPolyline.overlays(for: track)
                let waypoints = (track.waypoints ?? []).map { WaypointPin(trackID: track.id, waypoint: $0) }
                trackContent[track.id] = (overlays, waypoints)
                map.addOverlays(overlays, level: .aboveRoads)
                map.addAnnotations(waypoints)
            }
            return true
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = .systemPurple
            renderer.lineWidth = 3
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            let isWaypoint = annotation is WaypointPin
            guard isWaypoint || annotation is Pin else { return nil }
            let identifier = isWaypoint ? "GPX waypoint" : "Photo location"
            let marker = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
            marker.annotation = annotation
            marker.glyphImage = NSImage(systemSymbolName: isWaypoint ? "flag.fill" : "photo", accessibilityDescription: nil)
            let name = annotation.title ?? nil
            if isWaypoint {
                marker.markerTintColor = .systemPurple
                marker.setAccessibilityLabel(name.map { String(localized: "GPX waypoint \($0)") })
            } else {
                marker.setAccessibilityLabel(name)
            }
            return marker
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let waypoint = view.annotation as? WaypointPin,
               trackContent[waypoint.trackID]?.waypoints.contains(where: { $0 === waypoint }) == true {
                mapView.deselectAnnotation(waypoint, animated: false)
                onSelectWaypoint?(waypoint.trackID, waypoint.waypointID)
                return
            }
            guard let pin = view.annotation as? Pin, pin.point != selected else { return }
            onSelect?(pin.point)
        }
    }
}
