import IsoniqueCore
import MapKit
import SwiftUI

struct PhotoLocationLookupResult: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let address: String?
    let coordinates: GPSCoordinates
}

@MainActor
final class PhotoLocationLookup: ObservableObject {
    enum State: Equatable {
        case idle
        case searching
        case results([PhotoLocationLookupResult])
        case noResults
        case unavailable
    }

    @Published private(set) var state = State.idle
    private let search: @MainActor (String) async throws -> [PhotoLocationLookupResult]
    private var task: Task<Void, Never>?

    init(search: @escaping @MainActor (String) async throws -> [PhotoLocationLookupResult]) {
        self.search = search
    }

    convenience init() {
        self.init(search: Self.searchAppleMaps)
    }

    @discardableResult
    func submit(_ text: String) -> Task<Void, Never>? {
        cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        state = .searching
        let task = Task { [weak self, search] in
            let outcome: State
            do {
                try Task.checkCancellation()
                let matches = try await search(query)
                outcome = matches.isEmpty ? .noResults : .results(matches)
            } catch let error as MKError where error.code == .placemarkNotFound {
                outcome = .noResults
            } catch {
                outcome = .unavailable
            }
            guard !Task.isCancelled else { return }
            self?.task = nil
            self?.state = outcome
        }
        self.task = task
        return task
    }

    func choose(_ id: PhotoLocationLookupResult.ID) -> PhotoLocationLookupResult? {
        guard case .results(let matches) = state, let match = matches.first(where: { $0.id == id }) else { return nil }
        cancel()
        return match
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    private static func searchAppleMaps(_ query: String) async throws -> [PhotoLocationLookupResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        if #available(macOS 15.0, *) { request.resultTypes.insert(.physicalFeature) }
        let search = MKLocalSearch(request: request)
        let response = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await search.start()
        } onCancel: {
            Task { @MainActor in search.cancel() }
        }
        return response.mapItems.compactMap { item in
            let coordinate: CLLocationCoordinate2D
            let address: String?
            if #available(macOS 26.0, *) {
                coordinate = item.location.coordinate
                address = item.address?.fullAddress ?? item.addressRepresentations?.cityWithContext
            } else {
                coordinate = item.placemark.coordinate
                address = item.placemark.title
            }
            guard let coordinates = GPSCoordinates(latitude: coordinate.latitude, longitude: coordinate.longitude) else { return nil }
            let singleLineAddress = address?.split(whereSeparator: \.isNewline).joined(separator: ", ")
            let title = item.name ?? singleLineAddress ?? String(localized: "Unnamed location")
            return PhotoLocationLookupResult(title: title, address: singleLineAddress == title ? nil : singleLineAddress,
                                             coordinates: coordinates)
        }
    }
}
