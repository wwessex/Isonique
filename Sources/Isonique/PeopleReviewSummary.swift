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

    func offlineOriginals(in repository: LibraryRepository) async throws -> PeopleOfflineOriginals {
        let task = Task.detached(priority: .utility) {
            var offline: [Photo] = []
            for photo in originals {
                try Task.checkCancellation()
                if (try? repository.availableOriginalURL(photo)) == nil { offline.append(photo) }
            }
            return PeopleOfflineOriginals(offline)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

struct PeopleOfflineOriginals {
    let managed: [Photo]
    let referenced: [Photo]
    let originalIDs: Set<UUID>

    var count: Int { originalIDs.count }
    var reconnectAction: PeopleSummaryAction? {
        referenced.isEmpty ? nil : .reconnect(Set(referenced.map(\.originalID)))
    }

    init(_ photos: [Photo]) {
        let sorted = photos.sorted { $0.originalName.localizedStandardCompare($1.originalName) == .orderedAscending }
        managed = sorted.filter { $0.referencedPath == nil }
        referenced = sorted.filter { $0.referencedPath != nil }
        originalIDs = Set(photos.map(\.originalID))
    }
}

struct PeopleSummaryRequest: Identifiable {
    let id = UUID()
    let root: URL
    let initialScope: UnnamedFaceScope
}

enum PeopleSummaryAction: Equatable {
    case review(UnnamedFaceScope)
    case firstAid
    case reconnect(Set<UUID>)
}

extension Workspace {
    var currentPeopleReviewScope: UnnamedFaceScope { selectedProject.map { .project($0.id) } ?? .library }

    func openPeopleSummary(_ scope: UnnamedFaceScope) {
        guard canOpenUnnamedFaces, let repository else { return }
        peopleSummary = PeopleSummaryRequest(root: repository.root, initialScope: scope)
    }

    func scanUnscannedFaces(in scope: UnnamedFaceScope) {
        guard !busy, repository != nil else { return }
        let summary = PeopleReviewSummary(library: library, scope: scope)
        scanFaces(summary.unscannedVersions, availableOnly: true)
    }

    func continueFromPeopleSummary(_ action: PeopleSummaryAction) {
        guard canOpenUnnamedFaces, let request = peopleSummary, repository?.root == request.root else { return }
        pendingPeopleSummaryAction = (request.root, action)
        peopleSummary = nil
    }

    func finishPeopleSummary() {
        let pending = pendingPeopleSummaryAction
        pendingPeopleSummaryAction = nil
        guard let pending, repository?.root == pending.root else { return }
        switch pending.action {
        case .review(let scope): openUnnamedFaces(scope)
        case .firstAid: showLibraryFirstAid()
        case .reconnect(let ids): findOriginalsPanel(.reconnect, restrictedTo: ids)
        }
    }
}

struct PeopleReviewSummaryView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var scope: UnnamedFaceScope
    @State private var refresh = 0
    @State private var availability: Availability?
    @State private var requestedScan = false
    @State private var showOfflineOriginals = false

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
        let offline: PeopleOfflineOriginals
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
        let ready = offline.map { summary.availableVersionCount(offlineOriginals: $0.originalIDs) }

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
            DisclosureGroup("Show Offline Originals", isExpanded: $showOfflineOriginals) {
                offlineOriginalList(offline)
            }
            Divider()
            if let scan = model.peopleScan {
                PeopleScanProgressView(task: scan.task, progress: scan.progress)
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
                Button("Review Unnamed Faces…") { model.continueFromPeopleSummary(.review(scope)) }
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

    @ViewBuilder
    private func offlineOriginalList(_ offline: PeopleOfflineOriginals?) -> some View {
        if let offline, offline.count > 0 {
            VStack(alignment: .leading, spacing: 10) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if !offline.managed.isEmpty {
                            offlineGroup("Managed Originals", photos: offline.managed)
                        }
                        if !offline.referenced.isEmpty {
                            offlineGroup("Referenced Originals", photos: offline.referenced)
                        }
                    }
                    .padding(10)
                }
                .frame(height: min(235, CGFloat(offline.count) * 55 + 55))
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    if !offline.managed.isEmpty {
                        Button("Library First Aid…") { model.continueFromPeopleSummary(.firstAid) }
                            .help("Review storage issues in the entire library")
                    }
                    if let action = offline.reconnectAction {
                        Button("Reconnect Referenced Originals…") { model.continueFromPeopleSummary(action) }
                    }
                }
                .disabled(model.busy)
            }
            .padding(.top, 8)
        } else {
            if offline == nil {
                Text("Checking originals…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            } else {
                Text("All originals in this scope are available.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    private func offlineGroup(_ title: LocalizedStringKey, photos: [Photo]) -> some View {
        Section {
            ForEach(photos, id: \.originalID) { photo in
                let location = photo.referencedPath ?? "Originals/\(photo.filename)"
                VStack(alignment: .leading, spacing: 2) {
                    Text(photo.originalName).lineLimit(1)
                    Text(location).font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                }
                .help(location)
                .accessibilityElement(children: .combine)
            }
        } header: {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
        }
    }
}
