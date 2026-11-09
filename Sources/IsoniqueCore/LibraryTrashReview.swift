import Foundation

public struct LibraryTrashPhoto: Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let projectName: String?
}

public enum LibraryTrashOriginalDisposition: CaseIterable, Sendable {
    case finderTrashCandidate
    case retainedByActiveVersion
    case referenced
    case unavailable
}

public struct LibraryTrashOriginal: Identifiable, Sendable {
    public let id: UUID
    public let filename: String
    public let disposition: LibraryTrashOriginalDisposition
}

public struct LibraryTrashReview: Sendable {
    public let photos: [LibraryTrashPhoto]
    public let originals: [LibraryTrashOriginal]
}

public extension LibraryRepository {
    /// Inventory Library Trash using a saved catalogue snapshot and file metadata.
    func reviewEmptyLibraryTrash() throws -> LibraryTrashReview {
        let (_, library) = try LibraryBackup.readCatalogue(root)
        let trashed = library.photos.filter { $0.trashedAt != nil }
        guard !trashed.isEmpty else { return LibraryTrashReview(photos: [], originals: []) }

        let originals = try library.uniqueOriginals()
        let active = library.activePhotos
        let activeOriginalIDs = Set(active.map(\.originalID))
        let activeManagedNames = Set(active.filter { $0.referencedPath == nil }.map { trashStorageKey($0.filename) })
        let trashedOriginalIDs = Set(trashed.map(\.originalID))
        var managedNameCounts: [String: Int] = [:]
        for original in originals where original.referencedPath == nil {
            managedNameCounts[trashStorageKey(original.filename), default: 0] += 1
        }
        let projects = Dictionary(library.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let photos = trashed.map {
            LibraryTrashPhoto(id: $0.id, name: $0.displayName, projectName: $0.projectID.flatMap { projects[$0] })
        }
        var reviewedOriginals: [LibraryTrashOriginal] = []
        for original in originals where trashedOriginalIDs.contains(original.originalID) {
            try Task.checkCancellation()
            let disposition: LibraryTrashOriginalDisposition
            let key = trashStorageKey(original.filename)
            if original.referencedPath != nil {
                disposition = .referenced
            } else if activeOriginalIDs.contains(original.originalID) || activeManagedNames.contains(key) {
                disposition = .retainedByActiveVersion
            } else if managedNameCounts[key] == 1, let url = try? managedOriginalURL(original.filename),
                      (try? LibraryBackup.regularFile(url)) != nil {
                disposition = .finderTrashCandidate
            } else {
                disposition = .unavailable
            }
            reviewedOriginals.append(LibraryTrashOriginal(id: original.originalID, filename: original.filename,
                                                          disposition: disposition))
        }
        return LibraryTrashReview(photos: photos, originals: reviewedOriginals)
    }
}

// Default Mac volumes can resolve different spellings to the same directory entry.
private func trashStorageKey(_ filename: String) -> String {
    filename.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
        .precomposedStringWithCanonicalMapping
}
