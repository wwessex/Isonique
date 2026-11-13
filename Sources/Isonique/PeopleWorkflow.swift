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
    var issues: [String] = []
    var scanned = 0
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

    func scanSelectedFaces() {
        guard let repository else { return }
        let targets = metadataEditingTargets.filter { $0.people?.scanned != true }
        guard !targets.isEmpty else { return }
        let snapshot = library
        busy = true
        status = "Detecting faces on this Mac…"
        let task = Task.detached(priority: .userInitiated) {
            var result = PeopleScanResult()
            for photo in targets {
                try Task.checkCancellation()
                do {
                    let image = try repository.verifiedFaceSource(for: photo)
                    let regions = try await FaceDetection.regions(in: image)
                    var people = photo.people ?? PhotoPeople()
                    people.incorporateDetections(regions)
                    result.changes.append(PhotoPeopleChange(photoID: photo.id, people: people))
                    result.scanned += 1
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    result.issues.append("\(photo.displayName): \(error.localizedDescription)")
                }
            }
            return result
        }
        peopleScan = task
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
                status = result.scanned == 1 ? "Checked 1 photo version for faces" : "Checked \(result.scanned) photo versions for faces"
                if !result.issues.isEmpty {
                    error = "Skipped \(result.issues.count) photo versions.\n\n" + result.issues.prefix(8).joined(separator: "\n")
                }
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
        Button("Detect Faces in Selection", action: model.scanSelectedFaces)
            .disabled(!model.canScanSelectedFaces)
        if let scan = model.peopleScan {
            Button("Cancel Face Detection") { scan.cancel() }.disabled(scan.isCancelled)
        }
        Button("Review Faces…") {
            if let photo = model.selected { model.openPeopleReview(photo) }
        }.disabled(model.selected == nil || model.isViewingTrash || model.busy || model.batchMode)
        Button("Rename or Merge Person…") {
            if let group = model.selectedPersonGroup { model.openPersonNameEditor(group) }
        }.disabled(model.selectedPersonGroup == nil || model.busy)
    }
}
