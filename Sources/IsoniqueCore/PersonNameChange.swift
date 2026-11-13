import Foundation

public enum PersonNameAction: Equatable {
    case rename(String)
    case merge(intoKey: String)
}

public enum PersonNameError: LocalizedError {
    case missingSource, emptyName, existingName, missingDestination, samePerson, unchanged

    public var errorDescription: String? {
        switch self {
        case .missingSource: return String(localized: "This person is no longer in the library.")
        case .emptyName: return String(localized: "Enter a name.")
        case .existingName: return String(localized: "This name already belongs to a group. Choose Merge to combine the groups.")
        case .missingDestination: return String(localized: "Choose an existing person to merge into.")
        case .samePerson: return String(localized: "Choose a different person to merge into.")
        case .unchanged: return String(localized: "The name is already up to date.")
        }
    }
}

struct PersonRuleChange: Codable, Equatable {
    let albumID: UUID
    let criterionID: UUID
    let comparison: PhotoQueryOperator
    let before: String
    let after: String

    var reversed: Self {
        Self(albumID: albumID, criterionID: criterionID, comparison: comparison, before: after, after: before)
    }
}

public struct PersonNameHistory: Codable, Equatable {
    public let sourceKey: String
    public let destinationKey: String
    let photos: [PhotoPeopleChange]
    let rules: [PersonRuleChange]

    func excludingPhotos(_ ids: Set<UUID>) -> Self? {
        let kept = photos.filter { !ids.contains($0.photoID) }
        return kept.isEmpty && rules.isEmpty ? nil : Self(sourceKey: sourceKey, destinationKey: destinationKey,
                                                          photos: kept, rules: rules)
    }
}

public struct PersonNameReview {
    public struct AffectedPhoto: Identifiable {
        public let id: UUID
        public let name: String
        public let faceCount: Int
        public let inTrash: Bool
    }

    public struct AffectedRule: Identifiable {
        public var id: String { "\(change.albumID)/\(change.criterionID)" }
        public let album: String
        public var comparison: PhotoQueryOperator { change.comparison }
        public var before: String { change.before }
        public var after: String { change.after }
        fileprivate let change: PersonRuleChange
    }

    public let sourceName: String
    public let destinationName: String
    public let photos: [AffectedPhoto]
    public let rules: [AffectedRule]
    fileprivate let revision: CatalogueRevision?
    fileprivate let changes: PersonNameHistory
}

public extension Library {
    /// Include names found only in Trash so renaming cannot silently collide with a
    /// group that could later be restored. Prefer the spelling in active photos.
    var personNamesByKey: [String: String] {
        var names: [String: String] = [:]
        for trashed in [false, true] {
            for photo in photos where (photo.trashedAt != nil) == trashed {
                for name in photo.personNames {
                    let key = PhotoFace.personKey(name)
                    if names[key] == nil { names[key] = name }
                }
            }
        }
        return names
    }

    func reviewPersonName(_ sourceKey: String, action: PersonNameAction) throws -> PersonNameReview {
        let names = personNamesByKey
        guard let sourceName = names[sourceKey] else { throw PersonNameError.missingSource }
        let destination: String
        switch action {
        case .rename(let input):
            destination = PhotoFace.cleanedName(input)
            guard !destination.isEmpty else { throw PersonNameError.emptyName }
            let key = PhotoFace.personKey(destination)
            guard key == sourceKey || names[key] == nil else { throw PersonNameError.existingName }
        case .merge(let key):
            guard key != sourceKey else { throw PersonNameError.samePerson }
            guard let name = names[key] else { throw PersonNameError.missingDestination }
            destination = name
        }

        var affectedPhotos: [PersonNameReview.AffectedPhoto] = []
        var photoChanges: [PhotoPeopleChange] = []
        for photo in photos {
            guard var people = photo.people else { continue }
            var count = 0
            for index in people.faces.indices {
                guard let name = people.faces[index].name, name != destination,
                      PhotoFace.personKey(name) == sourceKey else { continue }
                people.faces[index].assignName(destination)
                count += 1
            }
            if count > 0 {
                affectedPhotos.append(.init(id: photo.id, name: photo.displayName, faceCount: count,
                                            inTrash: photo.trashedAt != nil))
                photoChanges.append(.init(photoID: photo.id, people: people))
            }
        }

        let rules = albums.flatMap { album in
            (album.rule?.query?.criteria ?? []).compactMap { criterion -> PersonNameReview.AffectedRule? in
                guard criterion.exactPersonKey == sourceKey, criterion.value != destination else { return nil }
                let change = PersonRuleChange(albumID: album.id, criterionID: criterion.id,
                                              comparison: criterion.comparison, before: criterion.value, after: destination)
                return .init(album: album.name, change: change)
            }
        }
        guard !photoChanges.isEmpty || !rules.isEmpty else { throw PersonNameError.unchanged }
        return PersonNameReview(sourceName: sourceName, destinationName: destination, photos: affectedPhotos, rules: rules,
                                revision: catalogueRevision,
                                changes: PersonNameHistory(sourceKey: sourceKey, destinationKey: PhotoFace.personKey(destination),
                                                           photos: photoChanges, rules: rules.map(\.change)))
    }

    mutating func applyPersonNameReview(_ review: PersonNameReview) -> PersonNameHistory? {
        guard catalogueRevision == review.revision else { return nil }
        return applyPersonNameChanges(review.changes, requireAllRules: true)
    }
}

extension Library {
    mutating func applyPersonNameChanges(_ changes: PersonNameHistory, requireAllRules: Bool = false) -> PersonNameHistory? {
        // Stage both changes together. A rule edited after this history entry was
        // recorded is left as edited, while unrelated rules in that album survive.
        var draft = self
        var inversePhotos: [PhotoPeopleChange] = []
        if !changes.photos.isEmpty {
            guard let previous = draft.replacePeople(changes.photos) else { return nil }
            inversePhotos = previous
        }
        var inverseRules: [PersonRuleChange] = []
        for change in changes.rules {
            guard let album = draft.albums.firstIndex(where: { $0.id == change.albumID }),
                  let criterion = draft.albums[album].rule?.query?.criteria.firstIndex(where: {
                      $0.id == change.criterionID && $0.field == .person &&
                          $0.comparison == change.comparison && $0.value == change.before
                  }) else {
                if requireAllRules { return nil }
                continue
            }
            draft.albums[album].rule?.query?.criteria[criterion].value = change.after
            inverseRules.append(change.reversed)
        }
        self = draft
        return PersonNameHistory(sourceKey: changes.destinationKey, destinationKey: changes.sourceKey,
                                 photos: inversePhotos, rules: inverseRules)
    }
}
