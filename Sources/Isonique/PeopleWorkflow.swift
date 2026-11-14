import IsoniqueCore
import SwiftUI

struct PeopleGroup: Identifiable {
    let id: String
    let name: String
    let photoCount: Int
    var scope: String { "person:\(id)" }

    static func groups(in photos: [Photo]) -> [Self] {
        var counts: [String: (name: String, count: Int)] = [:]
        for photo in photos where photo.trashedAt == nil {
            var counted: Set<String> = []
            for name in photo.personNames {
                let key = PhotoFace.personKey(name)
                guard counted.insert(key).inserted else { continue }
                let existing = counts[key, default: (name, 0)]
                counts[key] = (existing.name, existing.count + 1)
            }
        }
        return counts.map { Self(id: $0.key, name: $0.value.name, photoCount: $0.value.count) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct PeopleReview: Identifiable {
    let id = UUID()
    let photo: Photo
    let root: URL
}

struct PeopleScanResult {
    var changes: [PhotoPeopleChange] = []
    var skippedVersions: [PeopleScanSkip] = []
    var scanned: Int { changes.count }
    var skipped: Int { skippedVersions.count }
}

struct PeopleScanCounts: Equatable {
    let total: Int
    var checked = 0
    var skipped = 0
    var processed: Int { checked + skipped }
    var remaining: Int { total - processed }
}

// Publish per-version changes only to the progress controls.
@MainActor final class PeopleScanProgress: ObservableObject {
    @Published private(set) var counts: PeopleScanCounts
    @Published private(set) var isCancelling = false

    init(total: Int) {
        counts = PeopleScanCounts(total: total)
    }

    func record(checked: Int, skipped: Int) {
        guard !isCancelling else { return }
        counts = PeopleScanCounts(total: counts.total, checked: checked, skipped: skipped)
    }

    func cancel(_ task: Task<PeopleScanResult, Error>) {
        task.cancel()
        isCancelling = true
    }
}

struct PeopleScanJob {
    let task: Task<PeopleScanResult, Error>
    let progress: PeopleScanProgress
}

struct PeopleScanProgressView: View {
    let task: Task<PeopleScanResult, Error>
    @ObservedObject var progress: PeopleScanProgress

    var body: some View {
        let counts = progress.counts
        HStack(spacing: 12) {
            ProgressView(value: Double(counts.processed), total: Double(counts.total)) {
                if progress.isCancelling {
                    Text("Cancelling face detection…")
                } else {
                    Text("Detecting faces on this Mac…")
                }
            } currentValueLabel: {
                Text("\(counts.checked) checked · \(counts.skipped) skipped · \(counts.remaining) remaining")
                    .monospacedDigit()
            }
            Button("Cancel Scan") { progress.cancel(task) }
                .disabled(progress.isCancelling)
        }
    }
}

extension Workspace {
    var peopleGroups: [PeopleGroup] {
        if let peopleGroupsSnapshot { return peopleGroupsSnapshot }
        let groups = PeopleGroup.groups(in: library.photos)
        peopleGroupsSnapshot = groups
        return groups
    }

    func showPeople() {
        showBrowser(allPhotos: true)
        places = false
        batchMode = false
        batchSelection = []
        scope = "people-gallery"
        selection = nil
    }

    func showFacePhotos() {
        showBrowser(allPhotos: true)
        places = false
        scope = "people"
        selectAfterChange(preferred: selection)
    }

    func openPeopleReview(_ photo: Photo) {
        guard !busy, photo.trashedAt == nil, let repository else { return }
        peopleReview = PeopleReview(photo: photo, root: repository.root)
    }

    @discardableResult
    func applyPeopleReview(_ review: PeopleReview, people: PhotoPeople) -> Bool {
        guard repository?.root == review.root, let photo = library.photos.first(where: { $0.id == review.photo.id }),
              photo.trashedAt == nil, photo.sha256 == review.photo.sha256, photo.people == review.photo.people else {
            error = "The photo or its People records changed. Reopen Review Faces to continue."
            return false
        }
        let updated = people.hasData ? people : nil
        guard updated != photo.people else { return true }
        return commitPeople([PhotoPeopleChange(photoID: photo.id, people: updated)])
    }

    @discardableResult
    func commitPeople(_ changes: [PhotoPeopleChange]) -> Bool {
        var draft = library
        guard let previous = draft.replacePeople(changes) else { return false }
        var nextHistory = history
        nextHistory.record(.people(previous))
        guard commit(draft, history: nextHistory) else { return false }
        if selected == nil { selectAfterChange(preferred: selection) }
        batchSelection.formIntersection(photos.map(\.id))
        status = changes.count == 1 ? "Updated People for 1 photo version" : "Updated People for \(changes.count) photo versions"
        return true
    }

    var canScanSelectedFaces: Bool {
        metadataEditingTargets.contains { $0.people?.scanned != true }
    }

    func scanSelectedFaces(detect: @escaping @Sendable (CGImage) async throws -> [FaceRegion] = {
        try await FaceDetection.regions(in: $0)
    }) {
        scanFaces(metadataEditingTargets.filter { $0.people?.scanned != true }, detect: detect)
    }

    func scanFaces(_ targets: [Photo],
                   detect: @escaping @Sendable (CGImage) async throws -> [FaceRegion] = {
                       try await FaceDetection.regions(in: $0)
                   }) {
        guard !busy, let repository, !targets.isEmpty else { return }
        let snapshot = library
        let progress = PeopleScanProgress(total: targets.count)
        busy = true
        status = "Detecting faces on this Mac…"
        let task = Task.detached(priority: .userInitiated) {
            var result = PeopleScanResult()
            for photo in targets {
                try Task.checkCancellation()
                do {
                    let image = try repository.verifiedFaceSource(for: photo)
                    let regions = try await detect(image)
                    try Task.checkCancellation()
                    var people = photo.people ?? PhotoPeople()
                    people.incorporateDetections(regions)
                    result.changes.append(PhotoPeopleChange(photoID: photo.id, people: people))
                } catch is CancellationError {
                    throw CancellationError()
                } catch LibraryError.originalUnavailable {
                    try Task.checkCancellation()
                    result.skippedVersions.append(PeopleScanSkip(photo: photo, reason: .unavailable))
                } catch {
                    try Task.checkCancellation()
                    result.skippedVersions.append(PeopleScanSkip(photo: photo, reason: .processingFailed(error.localizedDescription)))
                }
                await progress.record(checked: result.scanned, skipped: result.skipped)
            }
            return result
        }
        peopleScan = PeopleScanJob(task: task, progress: progress)
        Task {
            defer { peopleScan = nil; busy = false }
            do {
                let result = try await task.value
                guard !task.isCancelled else { throw CancellationError() }
                guard self.repository?.root == repository.root, library.hasSameCatalogueRevision(as: snapshot) else {
                    error = "The catalogue changed. Start face detection again."
                    return
                }
                busy = false
                if !result.changes.isEmpty, !commitPeople(result.changes) {
                    status = "Face detection could not save its results"
                    return
                }
                let report = PeopleScanReport(root: repository.root, result: result)
                peopleScanReport = report
                status = report.summary
            } catch is CancellationError {
                status = "Face detection cancelled"
            } catch {
                self.error = error.localizedDescription
                status = "Face detection failed"
            }
        }
    }
}

struct PeopleCommands: View {
    @ObservedObject var model: Workspace

    var body: some View {
        Button("People Review Summary…") { model.openPeopleSummary(model.currentPeopleReviewScope) }
            .disabled(!model.canOpenUnnamedFaces)
        Button("Detect Faces in Selection") { model.scanSelectedFaces() }
            .disabled(!model.canScanSelectedFaces)
        if let scan = model.peopleScan {
            CancelPeopleScanCommand(task: scan.task, progress: scan.progress)
        }
        Button("Skipped Face Scan Results…") { model.showPeopleScanReport = true }
            .disabled(!model.canOpenPeopleScanReport)
        Button("Review Faces…") {
            if let photo = model.selected { model.openPeopleReview(photo) }
        }.disabled(model.selected == nil || model.isViewingTrash || model.busy || model.batchMode)
        Button("Review Unnamed Faces…") {
            model.openUnnamedFaces(model.currentPeopleReviewScope)
        }.disabled(!model.canOpenUnnamedFaces)
        Button("Rename or Merge Person…") {
            if let group = model.selectedPersonGroup { model.openPersonNameEditor(group) }
        }.disabled(model.selectedPersonGroup == nil || model.busy)
        Button("Person Overview…") {
            if let group = model.selectedPersonGroup { model.openPersonOverview(group) }
        }.disabled(model.selectedPersonGroup == nil || model.busy)
    }
}

private struct CancelPeopleScanCommand: View {
    let task: Task<PeopleScanResult, Error>
    @ObservedObject var progress: PeopleScanProgress

    var body: some View {
        Button("Cancel Face Detection") { progress.cancel(task) }
            .disabled(progress.isCancelling)
    }
}
