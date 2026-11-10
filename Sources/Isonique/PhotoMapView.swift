import AppKit
import IsoniqueCore
import MapKit

final class PhotoMapView: MKMapView {
    private var pendingFrame: MKMapRect?
    private let fitPadding = NSEdgeInsets(top: 32, left: 24, bottom: 24, right: 24)

    init(accessibilityLabel: String) {
        super.init(frame: .zero)
        let configuration = MKStandardMapConfiguration()
        configuration.pointOfInterestFilter = .excludingAll
        preferredConfiguration = configuration
        isRotateEnabled = false
        isPitchEnabled = false
        showsZoomControls = true
        showsScale = true
        setAccessibilityLabel(accessibilityLabel)
    }

    required init?(coder: NSCoder) { nil }

    func fit(_ rect: MKMapRect?) {
        pendingFrame = rect
        applyPendingFrame()
    }

    override func layout() {
        super.layout()
        applyPendingFrame()
    }

    func coordinate(at point: NSPoint) -> GPSCoordinates? {
        guard bounds.contains(point) else { return nil }
        let coordinate = convert(point, toCoordinateFrom: self)
        return GPSCoordinates(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private func applyPendingFrame() {
        guard let rect = pendingFrame, bounds.width > fitPadding.left + fitPadding.right,
              bounds.height > fitPadding.top + fitPadding.bottom else { return }
        pendingFrame = nil
        setVisibleMapRect(rect, edgePadding: fitPadding, animated: false)
    }
}

enum PhotoMapFraming {
    static func bounds(for coordinates: Set<GPSCoordinates>) -> MKMapRect? {
        let points = coordinates.map { MKMapPoint(CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)) }
        let worldWidth = MKMapRect.world.width
        let columns = points.map(\.x).sorted()
        let rows = points.map(\.y)
        guard let first = columns.first, let last = columns.last,
              let north = rows.min(), let south = rows.max() else { return nil }

        // Cut the wrapping map at its largest empty interval so nearby pins across the date line stay together.
        var start = first
        var largestGap = worldWidth - last + first
        for (left, right) in zip(columns, columns.dropFirst()) where right - left > largestGap {
            start = right
            largestGap = right - left
        }

        let width = worldWidth - largestGap
        let height = south - north
        let minimum = worldWidth * 0.06 / 360
        let paddedWidth = max(minimum, width * 1.001)
        let paddedHeight = max(minimum, height * 1.001)
        let left = (start + (width - paddedWidth) / 2 + worldWidth).truncatingRemainder(dividingBy: worldWidth)
        let top = min(max(0, north + (height - paddedHeight) / 2), worldWidth - paddedHeight)
        return MKMapRect(x: left, y: top, width: paddedWidth, height: paddedHeight)
    }
}
