import IsoniqueCore
import SwiftUI

struct ProjectLocationReview: Sendable {
    let editID: UUID
    let eligibleIDs: Set<UUID>
    let locatedCount: Int
    let clearedCount: Int
    let unverifiedCount: Int

    init(edit: PhotoLocationEdit, repository: LibraryRepository) throws {
        editID = edit.id
        let unindexedIDs = Set(edit.photos.lazy.filter { !$0.hasCataloguedLocation }.map(\.id))
        var checked = Library()
        checked.photos = edit.photos
        if !unindexedIDs.isEmpty {
            // Read the verified originals into a temporary catalogue for this preview.
            _ = try repository.catalogueGPS(for: unindexedIDs, in: &checked)
        }
        try Task.checkCancellation()

        var eligible = Set<UUID>()
        var located = 0
        var cleared = 0
        var unverified = 0
        for photo in checked.photos {
            if photo.cataloguedLocation != nil {
                located += 1
            } else if photo.locationOverride == .cleared {
                cleared += 1
            } else if photo.gpsIndex != nil {
                eligible.insert(photo.id)
            } else {
                unverified += 1
            }
        }
        eligibleIDs = eligible
        locatedCount = located
        clearedCount = cleared
        unverifiedCount = unverified
    }
}

extension Workspace {
    func openProjectLocationEditor() {
        guard !busy, let repository, let project = placesProject else { return }
        let versions = activeVersions(in: project.id)
        locationEditor = PhotoLocationEdit(action: .assign, libraryRoot: repository.root, photos: versions,
                                           project: .init(id: project.id, name: project.name))
    }

    func activeVersions(in projectID: UUID) -> [Photo] {
        library.photos.filter { $0.projectID == projectID && $0.trashedAt == nil }
    }
}

struct ProjectLocationPreview: View {
    let photos: [Photo]
    let review: ProjectLocationReview

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(review.eligibleIDs.count == 1 ? "1 version without a location" :
                    "\(review.eligibleIDs.count) versions without a location")
                .font(.headline)
            if review.locatedCount > 0 {
                Text("\(review.locatedCount) with existing locations")
            }
            if review.clearedCount > 0 {
                Text("\(review.clearedCount) with manually cleared locations")
            }
            if review.unverifiedCount > 0 {
                Text("\(review.unverifiedCount) with GPS unavailable for verification")
            }
            if !review.eligibleIDs.isEmpty {
                DisclosureGroup("Review Versions") {
                    List(photos.filter { review.eligibleIDs.contains($0.id) }) { photo in
                        Text(photo.displayName)
                    }.frame(height: 130)
                }
            }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
