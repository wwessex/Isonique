import Foundation

public enum VersionSource {
    case original
    case current
}

public extension Photo {
    var originalID: UUID { sharedOriginalID ?? id }
    var displayName: String { versionName ?? originalName }

    var exportBaseName: String {
        let name = versionName ?? (originalName as NSString).deletingPathExtension
        return name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    }

    mutating func useOriginal(from source: Photo) {
        filename = source.filename
        referencedPath = source.referencedPath
        sha256 = source.sha256
    }
}

public extension Library {
    mutating func createVersion(of id: UUID, from source: VersionSource) -> Photo? {
        guard let photo = photos.first(where: { $0.id == id && $0.trashedAt == nil }) else { return nil }
        let names = Set(photos.filter { $0.originalID == photo.originalID }.compactMap(\.versionName))
        let stem = (photo.originalName as NSString).deletingPathExtension
        var number = 2
        while names.contains("\(stem) — Version \(number)") { number += 1 }
        var version = photo
        version.id = UUID()
        version.sharedOriginalID = photo.originalID
        version.versionName = "\(stem) — Version \(number)"
        version.versions = nil
        if source == .original { version.adjustments = Adjustments() }
        self.version = max(self.version, 3)
        photos.append(version)
        return version
    }

    /// One storage record per original. Versions must agree on its location and fingerprint.
    func uniqueOriginals() throws -> [Photo] {
        var byID: [UUID: Photo] = [:]
        var filenames: Set<String> = []
        var photoIDs: Set<UUID> = []
        var originals: [Photo] = []
        for photo in photos {
            guard photoIDs.insert(photo.id).inserted, photo.sharedOriginalID != photo.id else {
                throw LibraryError.integrity("duplicate or invalid photo identity")
            }
            if let first = byID[photo.originalID] {
                guard first.filename == photo.filename, first.sha256 == photo.sha256,
                      first.referencedPath == photo.referencedPath else {
                    throw LibraryError.integrity("versions disagree on the original for \(photo.displayName)")
                }
            } else {
                guard filenames.insert(photo.filename).inserted else {
                    throw LibraryError.integrity("original filename is used by different originals")
                }
                byID[photo.originalID] = photo
                originals.append(photo)
            }
        }
        // A version can outlive its imported record, but it cannot identify another version as its original.
        for photo in photos {
            if photo.sharedOriginalID != nil, byID[photo.id] != nil {
                throw LibraryError.integrity("a version identifies another version as its original")
            }
        }
        return originals
    }

    /// Filename-based XML import addresses the imported photo, or its only remaining active version.
    func metadataTarget(named filename: String) -> UUID? {
        let matches = activePhotos.filter { ($0.sourceName ?? $0.originalName) == filename }
        guard let first = matches.first, matches.allSatisfy({ $0.originalID == first.originalID }) else { return nil }
        return matches.first { $0.id == $0.originalID }?.id ?? (matches.count == 1 ? first.id : nil)
    }

    mutating func applyHistory(_ entry: PhotoHistoryEntry) -> PhotoHistoryEntry? {
        switch entry {
        case .edit(let snapshot):
            guard let index = photos.firstIndex(where: { $0.id == snapshot.id }) else { return nil }
            let current = photos[index]
            var restored = snapshot
            restored.useOriginal(from: current)
            photos[index] = restored
            return .edit(current)
        case .removeVersion(let snapshot):
            guard let index = photos.firstIndex(where: { $0.id == snapshot.id && $0.sharedOriginalID != nil }),
                  photos.contains(where: { $0.id != snapshot.id && $0.originalID == snapshot.originalID }) else { return nil }
            return .restoreVersion(photos.remove(at: index))
        case .restoreVersion(let snapshot):
            guard snapshot.sharedOriginalID != nil, !photos.contains(where: { $0.id == snapshot.id }),
                  let source = photos.first(where: { $0.originalID == snapshot.originalID }) else { return nil }
            var restored = snapshot
            restored.useOriginal(from: source)
            photos.append(restored)
            return .removeVersion(restored)
        case .stackPick(let change):
            return .stackPick(applyStackPick(change))
        }
    }
}

public enum PhotoHistoryEntry: Codable, Equatable {
    case edit(Photo)
    case removeVersion(Photo)
    case restoreVersion(Photo)
    case stackPick(StackPickChange)

    public var photo: Photo? {
        switch self {
        case .edit(let photo), .removeVersion(let photo), .restoreVersion(let photo): return photo
        case .stackPick: return nil
        }
    }

    public var selectionID: UUID? {
        if case .stackPick(let change) = self { return change.selectionID }
        return photo?.id
    }

    var isEdit: Bool {
        if case .edit = self { return true }
        return false
    }
}

public struct EditHistory: Codable {
    public private(set) var undo: [PhotoHistoryEntry] = []
    public private(set) var redo: [PhotoHistoryEntry] = []

    public init() {}

    public mutating func record(_ photo: Photo) {
        record(.edit(photo))
    }

    public mutating func record(_ entry: PhotoHistoryEntry) {
        undo.append(entry)
        if undo.count > 100 { undo.removeFirst(undo.count - 100) }
        redo.removeAll()
    }

    public mutating func discardEmptiedTrash(photoIDs: Set<UUID>, originalIDs: Set<UUID>) {
        func isRemoved(_ entry: PhotoHistoryEntry) -> Bool {
            if let photo = entry.photo {
                return photoIDs.contains(photo.id) || originalIDs.contains(photo.originalID)
            }
            if case .stackPick(let change) = entry {
                return photoIDs.contains(change.selectionID) || change.photoID.map(photoIDs.contains) == true
            }
            return false
        }
        undo.removeAll(where: isRemoved)
        redo.removeAll(where: isRemoved)
    }

    public mutating func step(in library: inout Library, redoing: Bool) -> PhotoHistoryEntry? {
        guard let entry = redoing ? redo.last : undo.last, let inverse = library.applyHistory(entry) else { return nil }
        if redoing {
            redo.removeLast()
            undo.append(inverse)
        } else {
            undo.removeLast()
            redo.append(inverse)
        }
        return entry
    }

    private enum CodingKeys: String, CodingKey { case undo, redo, undoEntries, redoEntries }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        undo = try container.decodeIfPresent([PhotoHistoryEntry].self, forKey: .undoEntries)
            ?? container.decode([Photo].self, forKey: .undo).map(PhotoHistoryEntry.edit)
        redo = try container.decodeIfPresent([PhotoHistoryEntry].self, forKey: .redoEntries)
            ?? container.decode([Photo].self, forKey: .redo).map(PhotoHistoryEntry.edit)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if undo.allSatisfy(\.isEdit) && redo.allSatisfy(\.isEdit) {
            try container.encode(undo.compactMap(\.photo), forKey: .undo)
            try container.encode(redo.compactMap(\.photo), forKey: .redo)
        } else {
            try container.encode(undo, forKey: .undoEntries)
            try container.encode(redo, forKey: .redoEntries)
        }
    }
}
