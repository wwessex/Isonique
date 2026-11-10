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
    let iptc: IPTCMetadata?
    let keywords: String
    let keywordPaths: [KeywordPath]?
    let captureDate: String
    let locationOverride: PhotoLocationOverride?
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
        iptc = photo.iptc
        keywords = photo.keywords
        keywordPaths = photo.keywordPaths
        captureDate = photo.captureDate
        locationOverride = photo.locationOverride
        albumIDs = photo.albumIDs
        stackID = photo.stackID
        pairID = photo.pairID
    }

    func merging(_ current: Photo, with incoming: Photo, prefer preference: ProjectMergePreference,
                 representedAlbums: Set<UUID>, supportsLocationEdits: Bool = false) -> (photo: Photo, conflicts: [String]) {
        var result = Self.mergingEditableValues(current, with: incoming, baseline: self, prefer: preference,
                                                supportsLocationEdits: supportsLocationEdits)
        // Membership is a Boolean per album. Changes to distinct albums can both survive.
        let touchedAlbums = albumIDs.union(incoming.albumIDs).intersection(representedAlbums)
        for album in touchedAlbums where albumIDs.contains(album) != incoming.albumIDs.contains(album) {
            if incoming.albumIDs.contains(album) { result.photo.albumIDs.insert(album) }
            else { result.photo.albumIDs.remove(album) }
        }
        return result
    }

    static func mergingEditableValues(_ current: Photo, with incoming: Photo, baseline: Self?,
                                      prefer preference: ProjectMergePreference, supportsLocationEdits: Bool = false)
        -> (photo: Photo, conflicts: [String]) {
        var photo = current
        let edits = current.adjustments.mergingEdits(with: incoming.adjustments, baseline: baseline?.adjustments,
                                                     prefer: preference)
        photo.adjustments = edits.value
        var conflicts = edits.conflicts
        func apply<Value: Equatable>(_ field: WritableKeyPath<Photo, Value>, _ saved: KeyPath<Self, Value>, _ label: String) {
            let choice = resolveEditableValue(current[keyPath: field], incoming[keyPath: field],
                                              baseline: baseline.map { $0[keyPath: saved] }, prefer: preference)
            photo[keyPath: field] = choice.value
            if choice.conflict { conflicts.append(label) }
        }
        apply(\.versions, \.versions, "Saved recipes")
        apply(\.originalName, \.originalName, "Photo name")
        apply(\.versionName, \.versionName, "Version name")
        apply(\.rating, \.rating, "Rating")
        apply(\.flagged, \.flagged, "Flag")
        apply(\.colorLabel, \.colorLabel, String(localized: "Color label"))
        apply(\.caption, \.caption, "Caption")
        let iptcChanges = IPTCField.allCases.compactMap { field -> IPTCFieldEdit? in
            let old = current.iptc?[field]
            let new = incoming.iptc?[field]
            // An incoming catalogue without this field cannot explicitly clear it.
            if baseline == nil, new == nil { return nil }
            let choice = resolveEditableValue(old, new, baseline: baseline.map { $0.iptc?[field] }, prefer: preference)
            if choice.conflict { conflicts.append(field.title) }
            return choice.value == old ? nil : IPTCFieldEdit(field: field, values: choice.value)
        }
        if !iptcChanges.isEmpty { photo.applyIPTC(iptcChanges) }
        apply(\.keywords, \.keywords, "Keywords")
        apply(\.keywordPaths, \.keywordPaths, "Keyword paths")
        apply(\.captureDate, \.captureDate, "Capture date")
        // Absence can only mean "use the original" when the incoming export supports edits and has a baseline.
        if incoming.locationOverride != nil || (baseline != nil && supportsLocationEdits) {
            apply(\.locationOverride, \.locationOverride, "Location")
        }
        return (photo, conflicts)
    }
}

private func resolveEditableValue<Value: Equatable>(_ current: Value, _ incoming: Value, baseline: Value?,
                                                    prefer preference: ProjectMergePreference) -> (value: Value, conflict: Bool) {
    if let baseline { return resolveProjectValue(current, incoming, baseline: baseline, prefer: preference) }
    return (preference == .incoming ? incoming : current, current != incoming)
}

private extension Adjustments {
    func mergingEdits(with incoming: Adjustments, baseline: Adjustments?,
                      prefer preference: ProjectMergePreference) -> (value: Adjustments, conflicts: [String]) {
        guard self != incoming else { return (self, []) }
        var result = self
        var conflicts: [String] = []

        func resolve<Value: Equatable>(_ current: Value, _ incoming: Value, baseline: Value?, label: String) -> Value {
            let choice = resolveEditableValue(current, incoming, baseline: baseline, prefer: preference)
            if choice.conflict { conflicts.append(label) }
            return choice.value
        }

        func apply<Value: Equatable>(_ field: WritableKeyPath<Adjustments, Value>, _ label: String) {
            result[keyPath: field] = resolve(self[keyPath: field], incoming[keyPath: field],
                                             baseline: baseline.map { $0[keyPath: field] }, label: label)
        }

        func applyGroup(_ label: String, copy: (inout Adjustments, Adjustments) -> Void) {
            func projected(_ source: Adjustments) -> Adjustments {
                var group = Adjustments()
                copy(&group, source)
                return group
            }
            let group = resolve(projected(self), projected(incoming), baseline: baseline.map(projected), label: label)
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
    mutating func mergeAlbumDefinitions(from source: [Collection], baseline: [Collection],
                                        projectID: UUID, prefer preference: ProjectMergePreference) throws
        -> (updated: Int, conflicts: [ProjectAlbumMergeConflict]) {
        guard !baseline.isEmpty else { return (0, []) }
        let baselineByID = Dictionary(baseline.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let sourceByID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        let sharedAlbumIDs = albumIDsOutsideProject(projectID)
        var updated = 0
        var conflicts: [ProjectAlbumMergeConflict] = []
        for index in albums.indices {
            try Task.checkCancellation()
            let current = albums[index]
            guard let base = baselineByID[current.id], let incoming = sourceByID[current.id],
                  !sharedAlbumIDs.contains(current.id) else { continue }
            // A rule that changed scope or became a fixed membership list is a different definition.
            let regular = base.rule == nil && current.rule == nil && incoming.rule == nil
            let scopedSmart = base.rule?.projectID == projectID && current.rule?.projectID == projectID
                && incoming.rule?.projectID == projectID
            guard regular || scopedSmart else { continue }
            let name = resolveProjectValue(current.name, incoming.name, baseline: base.name, prefer: preference)
            let rule = resolveProjectValue(current.rule, incoming.rule, baseline: base.rule, prefer: preference)
            var fields: [String] = []
            if name.conflict { fields.append("Name") }
            if rule.conflict { fields.append("Smart Album Rules") }
            if !fields.isEmpty { conflicts.append(ProjectAlbumMergeConflict(albumName: current.name, fields: fields)) }
            if name.value != current.name || rule.value != current.rule {
                albums[index].name = name.value
                albums[index].rule = rule.value
                updated += 1
            }
        }
        return (updated, conflicts)
    }

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
