import IsoniqueCore
import SwiftUI

struct PeopleScanSkip: Identifiable, Equatable {
    enum Reason: Equatable {
        case unavailable
        case processingFailed(String)

        var detail: String {
            switch self {
            case .unavailable: return String(localized: "Original unavailable. Reconnect the drive or relink the original.")
            case .processingFailed(let message): return message
            }
        }
    }

    let id: UUID
    let name: String
    let reason: Reason

    init(photo: Photo, reason: Reason) {
        id = photo.id
        name = photo.displayName
        self.reason = reason
    }
}

struct PeopleScanReport: Identifiable {
    let id = UUID()
    let root: URL
    let checked: Int
    let skippedVersions: [PeopleScanSkip]

    init(root: URL, result: PeopleScanResult) {
        self.root = root
        checked = result.scanned
        skippedVersions = result.skippedVersions
    }

    var summary: String {
        let checkedText = checked == 1 ? String(localized: "Checked 1 photo version for faces")
            : String(localized: "Checked \(checked) photo versions for faces")
        let count = skippedVersions.count
        guard count > 0 else { return checkedText }
        let skippedText = count == 1 ? String(localized: "1 version skipped")
            : String(localized: "\(count) versions skipped")
        return checkedText + " · " + skippedText
    }
}

extension Workspace {
    var canOpenPeopleScanReport: Bool {
        guard !busy, let report = peopleScanReport, repository?.root == report.root else { return false }
        return !report.skippedVersions.isEmpty
    }

    func peopleScanRetryTargets(_ report: PeopleScanReport) -> [Photo] {
        guard peopleScanReport?.id == report.id, repository?.root == report.root else { return [] }
        let ids = Set(report.skippedVersions.map(\.id))
        return library.photos.filter { ids.contains($0.id) && $0.trashedAt == nil && $0.people?.scanned != true }
    }

    func retryPeopleScan(_ report: PeopleScanReport,
                         detect: @escaping @Sendable (CGImage) async throws -> [FaceRegion] = {
                             try await FaceDetection.regions(in: $0)
                         }) {
        scanFaces(peopleScanRetryTargets(report), detect: detect)
    }
}

struct PeopleScanReportView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var requestedRetry = false

    var body: some View {
        if let report = model.peopleScanReport, model.repository?.root == report.root {
            let eligibleCount = model.peopleScanRetryTargets(report).count
            VStack(alignment: .leading, spacing: 14) {
                Text("Skipped Face Scan Results").font(.title2.bold())
                Text(report.summary).foregroundStyle(.secondary)
                if report.skippedVersions.isEmpty {
                    Text("All retried versions were checked.")
                } else {
                    List(report.skippedVersions) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.name).font(.headline)
                            Text(row.reason.detail).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .combine)
                    }
                    .listStyle(.inset)
                    .accessibilityLabel("Skipped Photo Versions")
                    .frame(height: 240)
                    if eligibleCount == 0 {
                        Text("There are no unscanned versions from this report to retry.")
                            .foregroundStyle(.secondary)
                    }
                }
                if let scan = model.peopleScan {
                    PeopleScanProgressView(task: scan.task, progress: scan.progress)
                } else if requestedRetry && model.status != report.summary {
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    if !report.skippedVersions.isEmpty {
                        Button("Retry Skipped Versions (\(eligibleCount))") {
                            requestedRetry = true
                            model.retryPeopleScan(report)
                        }
                        .disabled(model.busy || eligibleCount == 0)
                    }
                    Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 570)
        }
    }
}
