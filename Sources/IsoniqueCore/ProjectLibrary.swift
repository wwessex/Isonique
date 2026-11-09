import Foundation

struct ProjectExportMembership: Codable {
    struct Original: Codable {
        let id: UUID
        let fingerprint: String

        init(_ photo: Photo) {
            id = photo.originalID
            fingerprint = photo.sha256
        }

        func matches(_ photo: Photo) -> Bool { id == photo.originalID && fingerprint == photo.sha256 }
    }

    let projectID: UUID
    let originalsByPhoto: [UUID: Original]
}

extension Library {
    func catalogueForProjectExport(_ projectID: UUID) throws -> Library {
        guard let project = projects.first(where: { $0.id == projectID }) else {
            throw LibraryError.integrity("selected project is missing")
        }
        let members = photos.filter { $0.projectID == projectID && $0.trashedAt == nil }
        var exported = Library()
        exported.version = version
        exported.projects = [project]
        exported.projectExportMembership = ProjectExportMembership(
            projectID: projectID,
            originalsByPhoto: Dictionary(members.map { ($0.id, ProjectExportMembership.Original($0)) },
                                        uniquingKeysWith: { first, _ in first }))
        exported.photos = members.map { photo in
            var copy = photo
            copy.referencedPath = nil
            return copy
        }

        let manualMemberships = Set(members.flatMap(\.albumIDs))
        var fixedMemberships: [UUID: Set<UUID>] = [:]
        for album in albums {
            try Task.checkCancellation()
            guard let rule = album.rule else {
                if manualMemberships.contains(album.id) { exported.albums.append(album) }
                continue
            }
            guard rule.projectID == nil || rule.projectID == projectID else { continue }
            // A successful export requires every included original to be available.
            let matching = Set(members.filter { rule.includes($0, originalAvailable: { true }) }.map(\.id))
            guard rule.projectID == projectID || !matching.isEmpty else { continue }
            var copy = album
            if rule.query?.criteria.contains(where: { $0.field == .storage }) == true {
                let managedMatches = Set(exported.photos.filter { rule.includes($0, originalAvailable: { true }) }.map(\.id))
                if matching != managedMatches {
                    copy.rule = nil
                    fixedMemberships[album.id] = matching
                }
            }
            exported.albums.append(copy)
        }
        let manualAlbumIDs = Set(exported.albums.filter { $0.rule == nil }.map(\.id))
        for index in exported.photos.indices {
            exported.photos[index].albumIDs.formIntersection(manualAlbumIDs)
            for (albumID, photoIDs) in fixedMemberships {
                if photoIDs.contains(exported.photos[index].id) {
                    exported.photos[index].albumIDs.insert(albumID)
                } else {
                    exported.photos[index].albumIDs.remove(albumID)
                }
            }
        }

        var stackCounts: [UUID: Int] = [:]
        var pairedOriginals: [UUID: Set<UUID>] = [:]
        for photo in exported.photos {
            if let stackID = photo.stackID { stackCounts[stackID, default: 0] += 1 }
            if let pairID = photo.pairID { pairedOriginals[pairID, default: []].insert(photo.originalID) }
        }
        let survivingStacks = Set(stackCounts.filter { StackRules.canStack(photoCount: $0.value) }.keys)
        let survivingPairs = Set(pairedOriginals.filter { $0.value.count > 1 }.keys)
        for index in exported.photos.indices {
            if let id = exported.photos[index].stackID, !survivingStacks.contains(id) {
                exported.photos[index].stackID = nil
            }
            if let id = exported.photos[index].pairID, !survivingPairs.contains(id) {
                exported.photos[index].pairID = nil
            }
        }

        if let stackBrowser {
            let byID = Dictionary(exported.photos.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var state = StackBrowserState()
            for stackID in stackBrowser.collapsed.intersection(survivingStacks) {
                state.setCollapsed(true, stackID: stackID)
            }
            for (stackID, photoID) in stackBrowser.picks where byID[photoID]?.stackID == stackID {
                _ = state.apply(StackPickChange(stackID: stackID, photoID: photoID, selectionID: photoID))
            }
            for (albumID, picks) in stackBrowser.albumPicks where manualAlbumIDs.contains(albumID) {
                for (stackID, photoID) in picks {
                    guard let photo = byID[photoID], photo.stackID == stackID, photo.albumIDs.contains(albumID) else { continue }
                    _ = state.apply(StackPickChange(stackID: stackID, albumID: albumID, photoID: photoID, selectionID: photoID))
                }
            }
            if state != StackBrowserState() { exported.stackBrowser = state }
        }
        try exported.validateSchema()
        return exported
    }
}
