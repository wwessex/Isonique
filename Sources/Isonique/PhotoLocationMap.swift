import AppKit
import IsoniqueCore
import MapKit
import SwiftUI

struct PhotoLocationMap: NSViewRepresentable {
    let point: GPSCoordinates?
    let locations: Set<GPSCoordinates>
    let onPick: (GPSCoordinates) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> PhotoMapView {
        let map = PhotoMapView(accessibilityLabel: String(localized: "Location assignment map"))
        let click = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pick))
        click.delegate = context.coordinator
        map.addGestureRecognizer(click)
        let framing: Set<GPSCoordinates> = point.map { [$0] } ?? locations
        map.fit(PhotoMapFraming.bounds(for: framing) ?? .world)
        return map
    }

    func updateNSView(_ map: PhotoMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPick = onPick
        guard coordinator.point != point else { return }
        if coordinator.point != nil { map.removeAnnotation(coordinator.pin) }
        coordinator.point = point
        if let point {
            coordinator.pin.coordinate = CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
            map.addAnnotation(coordinator.pin)
        }
    }

    final class Coordinator: NSObject, NSGestureRecognizerDelegate {
        let pin: MKPointAnnotation = {
            let annotation = MKPointAnnotation()
            annotation.title = String(localized: "Proposed location")
            return annotation
        }()
        var point: GPSCoordinates?
        var onPick: ((GPSCoordinates) -> Void)?

        @objc func pick(_ click: NSClickGestureRecognizer) {
            guard click.state == .ended, let map = click.view as? PhotoMapView,
                  let point = map.coordinate(at: click.location(in: map)) else { return }
            onPick?(point)
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                               shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
            guard let map = gestureRecognizer.view as? PhotoMapView,
                  let parent = map.superview else { return false }
            if event.type == .leftMouseDown && event.clickCount > 1 { return false }
            // Map controls keep their own click actions.
            guard let hit = map.hitTest(parent.convert(event.locationInWindow, from: nil)) else { return false }
            return !sequence(first: hit, next: { $0.superview })
                .prefix(while: { $0 !== map }).contains { $0 is NSControl }
        }

        func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: NSGestureRecognizer) -> Bool {
            true
        }
    }
}
