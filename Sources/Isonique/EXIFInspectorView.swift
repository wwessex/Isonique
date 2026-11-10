import IsoniqueCore
import SwiftUI

enum EXIFReadout {
    case loading
    case metadata(CameraEXIF)
    case offline
    case unreadable

    func value(for field: MetadataViewField) -> String {
        switch self {
        case .loading: return String(localized: "Reading…")
        case .offline: return String(localized: "Original offline")
        case .unreadable: return String(localized: "Unreadable")
        case .metadata(let exif):
            let value: String?
            switch field {
            case .shutterSpeed: value = exif.exposureSeconds.map(Self.shutterSpeed)
            case .aperture: value = exif.fNumber.map { "ƒ/\(Self.decimal($0))" }
            case .iso: value = exif.iso?.formatted(.number.grouping(.never))
            case .focalLength: value = exif.focalLengthMM.map { "\(Self.decimal($0)) mm" }
            case .lens: value = exif.lens
            default: value = nil
            }
            return value ?? String(localized: "Unavailable")
        }
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

struct EXIFMetadataReader<Content: View>: View {
    private struct Request: Equatable {
        let photoID: UUID
        let filename: String
        let referencedPath: String?
        let libraryRoot: URL?
        let originalRevision: Int
    }

    let photo: Photo
    @ViewBuilder var content: (EXIFReadout) -> Content

    @EnvironmentObject private var model: Workspace
    @State private var loaded: (request: Request, readout: EXIFReadout)?

    var body: some View {
        let request = Request(photoID: photo.id, filename: photo.filename, referencedPath: photo.referencedPath,
                              libraryRoot: model.repository?.root, originalRevision: model.originalStatusRevision)
        content(loaded?.request == request ? loaded?.readout ?? .loading : .loading)
            .task(id: request) {
                let repository = model.repository
                let photo = photo
                let readout = await Task.detached(priority: .userInitiated) {
                    guard let repository else { return EXIFReadout.offline }
                    do { return EXIFReadout.metadata(try repository.cameraEXIF(for: photo)) }
                    catch LibraryError.originalUnavailable(_) { return EXIFReadout.offline }
                    catch { return EXIFReadout.unreadable }
                }.value
                if !Task.isCancelled { loaded = (request, readout) }
            }
    }
}

struct EXIFInspectorView: View {
    let photo: Photo
    @State private var expanded = false

    var body: some View {
        DisclosureGroup("EXIF", isExpanded: $expanded) {
            if expanded {
                EXIFMetadataReader(photo: photo) { readout in
                    VStack(alignment: .leading, spacing: 8) {
                        switch readout {
                        case .metadata(let exif) where exif.isEmpty:
                            Text("No capture settings found in the original.").foregroundStyle(.secondary)
                        case .metadata:
                            ForEach(MetadataViewField.allCases.filter(\.isEXIF)) { field in
                                LabeledContent(field.label, value: readout.value(for: field))
                            }
                        case .offline:
                            Text("EXIF is unavailable while the original is offline.").foregroundStyle(.secondary)
                        case .unreadable:
                            Text("Could not read EXIF from the original.").foregroundStyle(.secondary)
                        case .loading:
                            ProgressView("Reading EXIF…").controlSize(.small)
                        }
                    }.textSelection(.enabled).padding(.top, 8)
                }
            }
        }
    }
}
