import Foundation

func resolveProjectValue<Value: Equatable>(_ current: Value, _ incoming: Value, baseline: Value,
                                           prefer preference: ProjectMergePreference) -> (value: Value, conflict: Bool) {
    if current == incoming || incoming == baseline { return (current, false) }
    if current == baseline { return (incoming, false) }
    return (preference == .incoming ? incoming : current, true)
}

/// Editable values as they appeared in the exported project.
struct ProjectPhotoMergeValues: Codable {
    let adjustments: Adjustments
    let versions: [PhotoVersion]?
    let originalName: String
    let versionName: String?
    let rating: Int
    let flagged: Bool
    let colorLabel: PhotoColorLabel?
    let caption: String
    let keywords: String
    let captureDate: String
    let albumIDs: Set<UUID>
    let stackID: UUID?
    let pairID: UUID?

    init(_ photo: Photo) {
        adjustments = photo.adjustments
        versions = photo.versions
        originalName = photo.originalName
        versionName = photo.versionName
        rating = photo.rating
        flagged = photo.flagged
        colorLabel = photo.colorLabel
        caption = photo.caption
        keywords = photo.keywords
        captureDate = photo.captureDate
        albumIDs = photo.albumIDs
        stackID = photo.stackID
        pairID = photo.pairID
    }

    func merging(_ current: Photo, with incoming: Photo, prefer preference: ProjectMergePreference,
                 representedAlbums: Set<UUID>) -> (photo: Photo, conflicts: [String]) {
        var photo = current
        var conflicts: [String] = []
        func apply<Value: Equatable>(_ field: WritableKeyPath<Photo, Value>, baseline: Value, label: String) {
            let choice = resolveProjectValue(current[keyPath: field], incoming[keyPath: field],
                                             baseline: baseline, prefer: preference)
            photo[keyPath: field] = choice.value
            if choice.conflict { conflicts.append(label) }
        }
        apply(\.adjustments, baseline: adjustments, label: "Adjustments")
        apply(\.versions, baseline: versions, label: "Saved recipes")
        apply(\.originalName, baseline: originalName, label: "Photo name")
        apply(\.versionName, baseline: versionName, label: "Version name")
        apply(\.rating, baseline: rating, label: "Rating")
        apply(\.flagged, baseline: flagged, label: "Flag")
        apply(\.colorLabel, baseline: colorLabel, label: "Color label")
        apply(\.caption, baseline: caption, label: "Caption")
        apply(\.keywords, baseline: keywords, label: "Keywords")
        apply(\.captureDate, baseline: captureDate, label: "Capture date")
        // Membership is a Boolean per album. Changes to distinct albums can both survive.
        let touchedAlbums = albumIDs.union(incoming.albumIDs).intersection(representedAlbums)
        for album in touchedAlbums where albumIDs.contains(album) != incoming.albumIDs.contains(album) {
            if incoming.albumIDs.contains(album) { photo.albumIDs.insert(album) }
            else { photo.albumIDs.remove(album) }
        }
        return (photo, conflicts)
    }
}
