import Foundation

struct PendingFinderTrash: Codable, Equatable {
    let filename: String
    let sha256: String
}

public struct EmptyLibraryTrashResult {
    public fileprivate(set) var library: Library
    public fileprivate(set) var removedPhotoIDs: Set<UUID> = []
    public fileprivate(set) var removedOriginalIDs: Set<UUID> = []
    public fileprivate(set) var movedToFinderTrash = 0
    public fileprivate(set) var alreadyAbsent = 0
    public fileprivate(set) var keptInLibrary = 0
    public fileprivate(set) var keptOriginals: [String] = []
    public fileprivate(set) var handoffErrors: [String] = []
    public var pendingFilenames: [String] { (library.pendingFinderTrash ?? []).map(\.filename) }
}

public extension LibraryRepository {
    func emptyLibraryTrash(after review: LibraryTrashReview, basedOn workspace: Library? = nil) throws -> EmptyLibraryTrashResult {
        try emptyLibraryTrash(after: review, basedOn: workspace) { original in
            try FileManager.default.trashItem(at: original, resultingItemURL: nil)
        }
    }

    internal func emptyLibraryTrash(after review: LibraryTrashReview, basedOn workspace: Library? = nil,
                                    trashSource: (URL) throws -> Void) throws
        -> EmptyLibraryTrashResult {
        guard review.root == root else { throw LibraryError.unsafePath }
        try Task.checkCancellation()
        return try withCatalogueWriteLock {
            let (catalogue, current) = try LibraryBackup.readCatalogue(root)
            guard catalogue == review.catalogue else {
                throw LibraryError.integrity("Library Trash changed; review it again")
            }
            try checkWorkspaceCatalogue(workspace, matches: current)
            var result = EmptyLibraryTrashResult(library: current)
            var removable: Set<UUID> = []
            var verified: [PendingFinderTrash] = []
            let originals = Dictionary(uniqueKeysWithValues: try current.uniqueOriginals().map { ($0.originalID, $0) })
            for item in review.originals {
                try Task.checkCancellation()
                switch item.disposition {
                case .retainedByActiveVersion, .referenced:
                    removable.insert(item.id)
                case .unavailable:
                    result.keptOriginals.append(item.filename)
                case .finderTrashCandidate:
                    guard let photo = originals[item.id], let url = try? managedOriginalURL(item.filename),
                          (try? Self.verifyOriginal(url, photo: photo)) != nil else {
                        result.keptOriginals.append(item.filename)
                        continue
                    }
                    removable.insert(item.id)
                    verified.append(PendingFinderTrash(filename: item.filename, sha256: photo.sha256))
                }
            }

            var draft = current
            let removed = current.photos.filter { $0.trashedAt != nil && removable.contains($0.originalID) }
            result.removedPhotoIDs = Set(removed.map(\.id))
            draft.photos.removeAll { result.removedPhotoIDs.contains($0.id) }
            result.keptInLibrary = review.photos.count - removed.count
            result.removedOriginalIDs = Set(removed.map(\.originalID)).subtracting(draft.photos.map(\.originalID))
            var pending = draft.pendingFinderTrash ?? []
            if !removed.isEmpty {
                draft.history?.discardEmptiedTrash(photoIDs: result.removedPhotoIDs, originalIDs: result.removedOriginalIDs)
                let emptiedStacks = Set(removed.compactMap(\.stackID)).subtracting(draft.photos.compactMap(\.stackID))
                draft.stackBrowser?.discardEmptiedTrash(photoIDs: result.removedPhotoIDs, stackIDs: emptiedStacks)
                let verifiedNames = Set(verified.map { managedFilenameKey($0.filename) })
                pending.removeAll { verifiedNames.contains(managedFilenameKey($0.filename)) }
                pending += verified
                draft.pendingFinderTrash = pending.isEmpty ? nil : pending
                try Task.checkCancellation()
                // A Finder failure can only leave an unreferenced file and a persisted retry entry.
                draft = try writeCatalogue(draft)
                result.library = draft
            }
            guard !pending.isEmpty else { return result }

            let claimedNames = Set(draft.photos.filter { $0.referencedPath == nil }.map { managedFilenameKey($0.filename) })
            var remaining: [PendingFinderTrash] = []
            for item in pending {
                // A new catalogue owner takes precedence over an earlier handoff request.
                if claimedNames.contains(managedFilenameKey(item.filename)) { continue }
                do {
                    let original = try managedOriginalURL(item.filename)
                    if try managedTrashFileExists(original) {
                        guard try Self.digest(original) == item.sha256 else { throw LibraryError.integrity(item.filename) }
                        try trashSource(original)
                        result.movedToFinderTrash += 1
                    } else {
                        // The move may have succeeded just before a process exit or a failed catalogue write.
                        result.alreadyAbsent += 1
                    }
                } catch {
                    remaining.append(item)
                    result.handoffErrors.append("\(item.filename) — \(error.localizedDescription)")
                }
            }
            if remaining != pending {
                draft.pendingFinderTrash = remaining.isEmpty ? nil : remaining
                do {
                    draft = try writeCatalogue(draft)
                    result.library = draft
                } catch {
                    result.handoffErrors.append("Finder Trash progress could not be saved. Review the remaining entries to retry.")
                }
            }
            return result
        }
    }

    private func managedTrashFileExists(_ original: URL) throws -> Bool {
        do {
            try LibraryBackup.regularFile(original)
            return true
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            let parent = original.deletingLastPathComponent()
            guard try parent.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else { throw error }
            return false
        }
    }
}
