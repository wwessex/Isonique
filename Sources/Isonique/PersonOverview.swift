import IsoniqueCore
import SwiftUI

struct PersonOverviewRequest: Identifiable {
    let id = UUID()
    let key: String
    let root: URL
}

struct PersonOverview {
    struct Face: Identifiable {
        struct ID: Hashable {
            let photoID: UUID
            let faceID: UUID
        }

        let photo: Photo
        let face: PhotoFace
        let number: Int
        var id: ID { ID(photoID: photo.id, faceID: face.id) }
    }

    struct ProjectCount: Identifiable {
        let id: UUID?
        let name: String
        let count: Int
    }

    let faces: [Face]
    let projectCounts: [ProjectCount]
    let photoCount: Int

    var chosenFace: Face? {
        faces.lazy.filter { $0.face.representativeChosenAt != nil }.max {
            ($0.face.representativeChosenAt ?? .distantPast) < ($1.face.representativeChosenAt ?? .distantPast)
        }
    }
    var portrait: Face? { chosenFace ?? faces.first }

    init(key: String, library: Library) {
        let matchingPhotos = library.activePhotos.filter { photo in
            photo.personNames.contains { PhotoFace.personKey($0) == key }
        }.sorted {
            $0.importedAt == $1.importedAt ? $0.id.uuidString < $1.id.uuidString : $0.importedAt < $1.importedAt
        }
        faces = matchingPhotos.flatMap { photo -> [Face] in
            (photo.people?.faces ?? []).enumerated().compactMap { index, face in
                guard let name = face.name, PhotoFace.personKey(name) == key else { return nil }
                return Face(photo: photo, face: face, number: index + 1)
            }
        }
        photoCount = matchingPhotos.count
        let projects = Dictionary(library.projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let grouped = Dictionary(grouping: matchingPhotos) { photo in
            photo.projectID.flatMap { projects[$0] != nil ? $0 : nil }
        }
        projectCounts = grouped.map { id, photos in
            ProjectCount(id: id, name: id.flatMap { projects[$0] } ?? String(localized: "No Project"), count: photos.count)
        }.sorted {
            if ($0.id == nil) != ($1.id == nil) { return $1.id == nil }
            let order = $0.name.localizedStandardCompare($1.name)
            if order != .orderedSame { return order == .orderedAscending }
            return ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "")
        }
    }
}

extension Workspace {
    func openPersonOverview(_ person: PeopleGroup) {
        guard !busy, let repository, peopleGroups.contains(where: { $0.id == person.id }) else { return }
        personOverview = PersonOverviewRequest(key: person.id, root: repository.root)
    }

    @discardableResult
    func setRepresentativeFace(_ candidate: PersonOverview.Face, for request: PersonOverviewRequest) -> Bool {
        guard !busy, personOverview?.id == request.id, repository?.root == request.root else { return false }
        guard let photo = library.photos.first(where: { $0.id == candidate.photo.id }), photo.trashedAt == nil,
              photo.sha256 == candidate.photo.sha256,
              let face = photo.people?.faces.first(where: { $0.id == candidate.face.id }), face == candidate.face,
              let name = face.name, PhotoFace.personKey(name) == request.key else {
            error = "The face has changed. Choose a face from the current overview."
            return false
        }
        if face.representativeChosenAt != nil,
           PersonOverview(key: request.key, library: library).chosenFace?.id == candidate.id { return true }

        let chosenAt = Date()
        let changes = library.photos.compactMap { photo -> PhotoPeopleChange? in
            guard var people = photo.people else { return nil }
            let previous = people
            for index in people.faces.indices {
                let face = people.faces[index]
                guard let name = face.name, PhotoFace.personKey(name) == request.key else { continue }
                let chosen = photo.id == candidate.photo.id && face.id == candidate.face.id
                if chosen || face.representativeChosenAt != nil {
                    people.faces[index].setRepresentative(chosenAt: chosen ? chosenAt : nil)
                }
            }
            return people == previous ? nil : PhotoPeopleChange(photoID: photo.id, people: people)
        }
        guard commitPeople(changes) else { return false }
        status = "Representative face saved"
        return true
    }

    func browsePerson(_ request: PersonOverviewRequest) {
        guard repository?.root == request.root,
              let person = peopleGroups.first(where: { $0.id == request.key }) else { return }
        showBrowser(allPhotos: true)
        places = false
        scope = person.scope
        selectAfterChange(preferred: selection)
        personOverview = nil
    }
}
