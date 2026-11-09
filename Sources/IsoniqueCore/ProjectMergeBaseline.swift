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
        let edits = adjustments.mergingProjectEdits(current.adjustments, with: incoming.adjustments, prefer: preference)
        photo.adjustments = edits.value
        var conflicts = edits.conflicts
        func apply<Value: Equatable>(_ field: WritableKeyPath<Photo, Value>, baseline: Value, label: String) {
            let choice = resolveProjectValue(current[keyPath: field], incoming[keyPath: field],
                                             baseline: baseline, prefer: preference)
            photo[keyPath: field] = choice.value
            if choice.conflict { conflicts.append(label) }
        }
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

private extension Adjustments {
    func mergingProjectEdits(_ current: Adjustments, with incoming: Adjustments,
                             prefer preference: ProjectMergePreference) -> (value: Adjustments, conflicts: [String]) {
        var result = current
        var conflicts: [String] = []

        func resolve<Value: Equatable>(_ current: Value, _ incoming: Value, baseline: Value, label: String) -> Value {
            let choice = resolveProjectValue(current, incoming, baseline: baseline, prefer: preference)
            if choice.conflict { conflicts.append(label) }
            return choice.value
        }

        func apply<Value: Equatable>(_ field: WritableKeyPath<Adjustments, Value>, _ label: String) {
            result[keyPath: field] = resolve(current[keyPath: field], incoming[keyPath: field],
                                             baseline: self[keyPath: field], label: label)
        }

        func applyGroup(_ label: String, copy: (inout Adjustments, Adjustments) -> Void) {
            func projected(_ source: Adjustments) -> Adjustments {
                var group = Adjustments()
                copy(&group, source)
                return group
            }
            let group = resolve(projected(current), projected(incoming), baseline: projected(self), label: label)
            copy(&result, group)
        }

        apply(\.exposure, "Exposure")
        apply(\.brightness, "Brightness")
        apply(\.vibrancy, "Vibrancy")
        apply(\.sepia, "Sepia")
        apply(\.contrast, "Contrast")
        apply(\.saturation, "Saturation")
        apply(\.warmth, "Temperature")
        apply(\.tint, "Tint")
        apply(\.shadows, "Shadows")
        apply(\.highlights, "Highlights")

        // Crop coordinates belong to the orientation and geometry in which they were edited.
        applyGroup(AdjustmentGroup.geometry.rawValue) { target, source in
            target = source.stamping(onto: target, groups: [.geometry])
        }
        applyGroup("Levels") { target, source in
            target.blackPoint = source.blackPoint
            target.whitePoint = source.whitePoint
            target.gamma = source.gamma
            target.levelQuarterTones = source.levelQuarterTones
        }
        applyGroup("Curves") { target, source in
            target.curveShadows = source.curveShadows
            target.curveMidtones = source.curveMidtones
            target.curveHighlights = source.curveHighlights
        }
        apply(\.channelCurves, "Channel Curves")
        apply(\.channelLevels, "Channel Levels")
        apply(\.localBrushes, AdjustmentGroup.localBrush.rawValue)
        return (result, conflicts)
    }
}

extension Library {
    mutating func mergeStackPresentation(from source: Library, baseline: StackBrowserState,
                                         prefer preference: ProjectMergePreference, appliedPhotos: Set<UUID>,
                                         excludedStacks: Set<UUID>, regularAlbums: Set<UUID>)
        -> (updated: Int, conflicts: [ProjectStackMergeConflict]) {
        let incoming = source.stackBrowser ?? StackBrowserState()
        let current = stackBrowser ?? StackBrowserState()
        let incomingPhotos = source.activePhotos
        let mergedPhotos = activePhotos
        let incomingGroups = Dictionary(grouping: incomingPhotos, by: \.stackID)
        let groups = Dictionary(grouping: mergedPhotos, by: \.stackID)
        let scopedStacks = Set(groups.compactMap { stackID, members -> UUID? in
            guard let stackID, members.count > 1, (incomingGroups[stackID]?.count ?? 0) > 1,
                  !excludedStacks.contains(stackID), members.allSatisfy({ appliedPhotos.contains($0.id) }) else { return nil }
            return stackID
        })
        guard !scopedStacks.isEmpty else { return (0, []) }

        let photosByID = Dictionary(uniqueKeysWithValues: mergedPhotos.map { ($0.id, $0) })
        let incomingByID = Dictionary(uniqueKeysWithValues: incomingPhotos.map { ($0.id, $0) })
        var state = current
        var updated: Set<UUID> = []
        var conflicts: [UUID: [String]] = [:]
        func mergePick(stackID: UUID, album: Collection?, old: UUID?, imported: UUID?, base: UUID?) {
            guard old != imported, imported != base else { return }
            // A choice rejected by the photo or membership merge cannot become the cover.
            if let imported {
                guard let photo = photosByID[imported], photo.stackID == stackID,
                      let sourcePhoto = incomingByID[imported], sourcePhoto.stackID == stackID else { return }
                if let album, !photo.albumIDs.contains(album.id) || !sourcePhoto.albumIDs.contains(album.id) { return }
            }
            let choice = resolveProjectValue(old, imported, baseline: base, prefer: preference)
            if choice.conflict {
                let label = album.map { "Album Pick (\($0.name))" } ?? "Stack Pick"
                conflicts[stackID, default: []].append(label)
            }
            if choice.value != old, let selectionID = old ?? imported {
                _ = state.apply(StackPickChange(stackID: stackID, albumID: album?.id,
                                                photoID: choice.value, selectionID: selectionID))
                updated.insert(stackID)
            }
        }

        for stackID in scopedStacks {
            let old = current.collapsed.contains(stackID)
            let collapsed = resolveProjectValue(old, incoming.collapsed.contains(stackID),
                                                baseline: baseline.collapsed.contains(stackID), prefer: preference).value
            if collapsed != old {
                state.setCollapsed(collapsed, stackID: stackID)
                updated.insert(stackID)
            }
            mergePick(stackID: stackID, album: nil, old: current.picks[stackID],
                      imported: incoming.picks[stackID], base: baseline.picks[stackID])
        }
        for album in albums where regularAlbums.contains(album.id) {
            let old = current.albumPicks[album.id] ?? [:]
            let imported = incoming.albumPicks[album.id] ?? [:]
            let base = baseline.albumPicks[album.id] ?? [:]
            for stackID in Set(imported.keys).union(base.keys).intersection(scopedStacks) {
                mergePick(stackID: stackID, album: album, old: old[stackID], imported: imported[stackID], base: base[stackID])
            }
        }

        if !updated.isEmpty {
            stackBrowser = state == StackBrowserState() ? nil : state
            version = max(version, 3)
        }
        let review = conflicts.keys.sorted { $0.uuidString < $1.uuidString }.compactMap { stackID -> ProjectStackMergeConflict? in
            guard let representative = groups[stackID]?.first, let fields = conflicts[stackID] else { return nil }
            return ProjectStackMergeConflict(representativeName: representative.displayName, fields: fields)
        }
        return (updated.count, review)
    }
}
