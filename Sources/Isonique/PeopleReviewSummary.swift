import IsoniqueCore
import SwiftUI

struct PeopleReviewSummary {
    let unscannedVersions: [Photo]
    let unnamedFaceCount: Int
    let originals: [Photo]

    init(library: Library, scope: UnnamedFaceScope) {
        var unscanned: [Photo] = []
        var unnamed = 0
        var originals: [Photo] = []
        var seenOriginals: Set<UUID> = []
        for photo in library.photos where scope.includes(photo) {
            if photo.people?.scanned != true { unscanned.append(photo) }
            for face in photo.people?.faces ?? [] where face.name == nil { unnamed += 1 }
            if seenOriginals.insert(photo.originalID).inserted { originals.append(photo) }
        }
        unscannedVersions = unscanned
        unnamedFaceCount = unnamed
        self.originals = originals
    }

    func availableVersionCount(offlineOriginals: Set<UUID>) -> Int {
        unscannedVersions.count { !offlineOriginals.contains($0.originalID) }
    }

    func offlineOriginals(in repository: LibraryRepository) async throws -> Set<UUID> {
        let task = Task.detached(priority: .utility) {
            var offline: Set<UUID> = []
            for photo in originals {
                try Task.checkCancellation()
                if (try? repository.availableOriginalURL(photo)) == nil { offline.insert(photo.originalID) }
            }
            return offline
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

struct PeopleSummaryRequest: Identifiable {
    let id = UUID()
    let initialScope: UnnamedFaceScope
}

extension Workspace {
    var currentPeopleReviewScope: UnnamedFaceScope { selectedProject.map { .project($0.id) } ?? .library }

    func openPeopleSummary(_ scope: UnnamedFaceScope) {
        guard canOpenUnnamedFaces else { return }
        peopleSummary = PeopleSummaryRequest(initialScope: scope)
    }

    func scanUnscannedFaces(in scope: UnnamedFaceScope) {
        guard !busy, repository != nil else { return }
        let summary = PeopleReviewSummary(library: library, scope: scope)
        scanFaces(summary.unscannedVersions, availableOnly: true)
    }

    func reviewFacesFromSummary(in scope: UnnamedFaceScope) {
        guard canOpenUnnamedFaces, peopleSummary != nil else { return }
        pendingUnnamedFaceScope = scope
        peopleSummary = nil
    }

    func finishPeopleSummary() {
        guard let scope = pendingUnnamedFaceScope else { return }
        pendingUnnamedFaceScope = nil
        openUnnamedFaces(scope)
    }
}

struct PeopleReviewSummaryView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var scope: UnnamedFaceScope
    @State private var refresh = 0
    @State private var availability: Availability?
    @State private var requestedScan = false

    private struct OriginalLocation: Equatable {
        let id: UUID
        let filename: String
        let reference: String?
    }

    private struct AvailabilityKey: Equatable {
        let root: URL?
        let originals: [OriginalLocation]
        let revision: Int
        let refresh: Int
    }

    private struct Availability {
        let key: AvailabilityKey
        let offline: Set<UUID>
    }

    init(request: PeopleSummaryRequest) {
        _scope = State(initialValue: request.initialScope)
    }

    var body: some View {
        let summary = PeopleReviewSummary(library: model.library, scope: scope)
        let key = AvailabilityKey(root: model.repository?.root, originals: summary.originals.map {
            OriginalLocation(id: $0.originalID, filename: $0.filename, reference: $0.referencedPath)
        }, revision: model.originalStatusRevision, refresh: refresh)
        let offline = availability?.key == key ? availability?.offline : nil
        let ready = offline.map { summary.availableVersionCount(offlineOriginals: $0) }

        VStack(alignment: .leading, spacing: 16) {
            Text("People Review Summary").font(.title2.bold())
            Picker("Scope", selection: $scope) {
                Text("Entire Library").tag(UnnamedFaceScope.library)
                ForEach(model.library.projects) { project in
                    Text(project.name).tag(UnnamedFaceScope.project(project.id))
                }
            }
            .disabled(model.peopleScan != nil)

            VStack(spacing: 10) {
                LabeledContent("Unscanned Photo Versions", value: summary.unscannedVersions.count.formatted())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Unscanned Photo Versions")
                    .accessibilityValue(summary.unscannedVersions.count.formatted())
                LabeledContent("Unnamed Faces", value: summary.unnamedFaceCount.formatted())
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Unnamed Faces")
                    .accessibilityValue(summary.unnamedFaceCount.formatted())
                LabeledContent("Offline Originals") {
                    if let offline {
                        Text(offline.count.formatted())
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Offline Originals")
                .accessibilityValue(offline.map { $0.count.formatted() } ?? String(localized: "Checking originals"))
            }
            .monospacedDigit()
            Divider()
            if let scan = model.peopleScan {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Detecting faces on this Mac…")
                    Spacer()
                    Button("Cancel Scan") { scan.cancel() }
                }
            } else if requestedScan {
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                let scanTitle = ready.map { String(localized: "Scan Available Photos (\($0.formatted()))") }
                    ?? String(localized: "Scan Available Photos")
                Button(scanTitle) {
                    requestedScan = true
                    model.scanUnscannedFaces(in: scope)
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
                .disabled(model.busy || (ready ?? 0) == 0)
                Button("Review Unnamed Faces…") { model.reviewFacesFromSummary(in: scope) }
                    .keyboardShortcut("r", modifiers: [.command, .option])
                    .disabled(model.busy || summary.unnamedFaceCount == 0)
                Spacer()
                Button("Refresh") { refresh += 1 }
                    .disabled(model.peopleScan != nil)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(20)
        .frame(width: 605)
        .onChange(of: model.library.projects.map(\.id)) { _, ids in
            if case .project(let id) = scope, !ids.contains(id) { scope = .library }
        }
        .onChange(of: scope) { requestedScan = false }
        .onChange(of: model.peopleScan != nil) { wasScanning, isScanning in
            if wasScanning && !isScanning { refresh += 1 }
        }
        .task(id: key) {
            guard let repository = model.repository,
                  let offline = try? await summary.offlineOriginals(in: repository), !Task.isCancelled else { return }
            availability = Availability(key: key, offline: offline)
        }
    }
}
