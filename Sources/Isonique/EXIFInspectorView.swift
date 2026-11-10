import IsoniqueCore
import SwiftUI

struct EXIFInspectorView: View {
    private struct Request: Equatable {
        let photoID: UUID
        let filename: String
        let referencedPath: String?
        let libraryRoot: URL?
        let originalRevision: Int
    }

    private enum Readout {
        case metadata(CameraEXIF)
        case offline
        case unreadable
    }

    let photo: Photo

    @EnvironmentObject private var model: Workspace
    @State private var expanded = false
    @State private var loaded: (request: Request, readout: Readout)?

    var body: some View {
        let request = Request(photoID: photo.id, filename: photo.filename, referencedPath: photo.referencedPath,
                              libraryRoot: model.repository?.root, originalRevision: model.originalStatusRevision)
        DisclosureGroup("EXIF", isExpanded: $expanded) {
            if expanded {
                VStack(alignment: .leading, spacing: 8) {
                    switch loaded?.request == request ? loaded?.readout : nil {
                    case .metadata(let exif) where exif.isEmpty:
                        Text("No capture settings found in the original.").foregroundStyle(.secondary)
                    case .metadata(let exif):
                        LabeledContent("Shutter speed", value: exif.exposureSeconds.map(Self.shutterSpeed) ?? Self.unavailable)
                        LabeledContent("Aperture", value: exif.fNumber.map { "ƒ/\(Self.decimal($0))" } ?? Self.unavailable)
                        LabeledContent("ISO", value: exif.iso?.formatted(.number.grouping(.never)) ?? Self.unavailable)
                        LabeledContent("Focal length", value: exif.focalLengthMM.map { "\(Self.decimal($0)) mm" } ?? Self.unavailable)
                        LabeledContent("Lens", value: exif.lens ?? Self.unavailable)
                    case .offline:
                        Text("EXIF is unavailable while the original is offline.").foregroundStyle(.secondary)
                    case .unreadable:
                        Text("Could not read EXIF from the original.").foregroundStyle(.secondary)
                    case nil:
                        ProgressView("Reading EXIF…").controlSize(.small)
                    }
                }
                .textSelection(.enabled)
                .padding(.top, 8)
                .task(id: request) {
                    let repository = model.repository
                    let photo = photo
                    let readout = await Task.detached(priority: .userInitiated) {
                        guard let repository else { return Readout.offline }
                        do { return Readout.metadata(try repository.cameraEXIF(for: photo)) }
                        catch LibraryError.originalUnavailable(_) { return Readout.offline }
                        catch { return Readout.unreadable }
                    }.value
                    if !Task.isCancelled { loaded = (request, readout) }
                }
            }
        }
        .onChange(of: expanded) { if !expanded { loaded = nil } }
    }

    private static var unavailable: String { String(localized: "Unavailable") }

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
