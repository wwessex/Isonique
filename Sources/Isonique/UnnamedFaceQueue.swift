import IsoniqueCore
import SwiftUI

enum UnnamedFaceScope: Hashable {
    case library
    case project(UUID)

    func includes(_ photo: Photo) -> Bool {
        guard photo.trashedAt == nil else { return false }
        switch self {
        case .library: return true
        case .project(let id): return photo.projectID == id
        }
    }
}

struct UnnamedFaceItem: Identifiable {
    struct ID: Hashable {
        let photoID: UUID
        let faceID: UUID
    }

    let photo: Photo
    let face: PhotoFace
    let number: Int
    let faceCount: Int
    var id: ID { ID(photoID: photo.id, faceID: face.id) }

    static func queue(in library: Library, scope: UnnamedFaceScope) -> [Self] {
        let candidates = library.photos.filter {
            scope.includes($0) && $0.people?.faces.contains(where: { $0.name == nil }) == true
        }.sorted {
            $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt < $1.importedAt
        }
        return candidates.flatMap { photo -> [Self] in
            let faces = photo.people?.faces ?? []
            return faces.enumerated().compactMap { offset, face in
                guard face.name == nil else { return nil }
                return Self(photo: photo, face: face, number: offset + 1, faceCount: faces.count)
            }
        }
    }
}

struct UnnamedFaceReview: Identifiable {
    let id = UUID()
    let root: URL
    let initialScope: UnnamedFaceScope
}

enum UnnamedFaceDecision {
    case existingName(String)
    case newName(String)
    case dismiss
}

extension Workspace {
    var canOpenUnnamedFaces: Bool { repository != nil && !busy }

    func openUnnamedFaces(_ scope: UnnamedFaceScope) {
        guard canOpenUnnamedFaces, let repository else { return }
        unnamedFaceReview = UnnamedFaceReview(root: repository.root, initialScope: scope)
    }

    func unnamedFaces(in scope: UnnamedFaceScope) -> [UnnamedFaceItem] {
        if let snapshot = unnamedFaceQueueSnapshot, snapshot.scope == scope { return snapshot.items }
        let items = UnnamedFaceItem.queue(in: library, scope: scope)
        unnamedFaceQueueSnapshot = (scope, items)
        return items
    }

    @discardableResult
    func resolveUnnamedFace(_ item: UnnamedFaceItem, in scope: UnnamedFaceScope,
                            review: UnnamedFaceReview, decision: UnnamedFaceDecision) -> Bool {
        guard !busy, unnamedFaceReview?.id == review.id, repository?.root == review.root else { return false }
        guard let photo = library.photos.first(where: { $0.id == item.photo.id }),
              scope.includes(photo), photo.sha256 == item.photo.sha256, var people = photo.people,
              let index = people.faces.firstIndex(where: { $0.id == item.face.id }),
              people.faces[index] == item.face, item.face.name == nil else {
            error = "This face changed. Review the current queue before continuing."
            return false
        }
        switch decision {
        case .existingName(let key):
            guard let group = peopleGroups.first(where: { $0.id == key }) else {
                error = "This name is no longer available. Choose a name again."
                return false
            }
            people.faces[index].assignName(group.name)
        case .newName(let input):
            let cleaned = PhotoFace.cleanedName(input)
            guard !cleaned.isEmpty else {
                error = "Enter a name."
                return false
            }
            // Reuse the saved spelling if the typed name already belongs to a group.
            let name = peopleGroups.first { $0.id == PhotoFace.personKey(cleaned) }?.name ?? cleaned
            people.faces[index].assignName(name)
        case .dismiss:
            people.removeFace(item.face.id)
        }
        return commitPeople([PhotoPeopleChange(photoID: photo.id, people: people)])
    }
}
