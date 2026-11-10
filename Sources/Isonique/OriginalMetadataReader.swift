import IsoniqueCore
import SwiftUI

enum OriginalMetadataReadout: Sendable {
    case loading
    case metadata(OriginalPhotoMetadata)
    case offline
    case unreadable

    func value(for field: MetadataViewField) -> String {
        switch self {
        case .loading: return String(localized: "Reading…")
        case .offline: return String(localized: "Original offline")
        case .unreadable: return String(localized: "Unreadable")
        case .metadata(let metadata):
            let exif = metadata.exif
            let value: String?
            switch field {
            case .shutterSpeed: value = exif.exposureSeconds.map(Self.shutterSpeed)
            case .aperture: value = exif.fNumber.map { "ƒ/\(Self.decimal($0))" }
            case .iso: value = exif.iso?.formatted(.number.grouping(.never))
            case .focalLength: value = exif.focalLengthMM.map { "\(Self.decimal($0)) mm" }
            case .lens: value = exif.lens
            case .latitude: value = metadata.gps.map { Self.coordinate($0.latitude) }
            case .longitude: value = metadata.gps.map { Self.coordinate($0.longitude) }
            default: value = nil
            }
            return value ?? String(localized: "Unavailable")
        }
    }

    private static func coordinate(_ value: Double) -> String {
        value.formatted(.number.grouping(.never).precision(.fractionLength(0...6))) + "°"
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private static func shutterSpeed(_ seconds: Double) -> String {
        let reciprocal = 1 / seconds
        if let denominator = Int(exactly: reciprocal.rounded()), denominator >= 2,
           abs(reciprocal - Double(denominator)) / reciprocal < 0.005 {
            return "1/\(denominator.formatted(.number.grouping(.never))) s"
        }
        return "\(seconds.formatted(.number.precision(.significantDigits(1...6)))) s"
    }
}

struct OriginalMetadataReader<Content: View>: View {
    private struct Request: Equatable {
        let photoID: UUID
        let filename: String
        let referencedPath: String?
        let libraryRoot: URL?
        let originalRevision: Int
    }

    let photo: Photo
    @ViewBuilder var content: (OriginalMetadataReadout) -> Content

    @EnvironmentObject private var model: Workspace
    @State private var loaded: (request: Request, readout: OriginalMetadataReadout)?

    var body: some View {
        let request = Request(photoID: photo.id, filename: photo.filename, referencedPath: photo.referencedPath,
                              libraryRoot: model.repository?.root, originalRevision: model.originalStatusRevision)
        content(loaded?.request == request ? loaded?.readout ?? .loading : .loading)
            .task(id: request) {
                let repository = model.repository
                let photo = photo
                let readout = await Task.detached(priority: .userInitiated) {
                    guard let repository else { return OriginalMetadataReadout.offline }
                    do { return OriginalMetadataReadout.metadata(try repository.originalMetadata(for: photo)) }
                    catch LibraryError.originalUnavailable(_) { return OriginalMetadataReadout.offline }
                    catch { return OriginalMetadataReadout.unreadable }
                }.value
                if !Task.isCancelled { loaded = (request, readout) }
            }
    }
}
