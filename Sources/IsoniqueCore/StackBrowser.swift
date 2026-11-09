import Foundation

public struct StackPickChange: Codable, Equatable {
    public let stackID: UUID
    public let albumID: UUID?
    public let photoID: UUID?
    public let selectionID: UUID

    public init(stackID: UUID, albumID: UUID? = nil, photoID: UUID?, selectionID: UUID) {
        self.stackID = stackID
        self.albumID = albumID
        self.photoID = photoID
        self.selectionID = selectionID
    }
}

public struct StackBrowserState: Codable, Equatable {
    public private(set) var picks: [UUID: UUID] = [:]
    public private(set) var albumPicks: [UUID: [UUID: UUID]] = [:]
    public private(set) var collapsed: Set<UUID> = []

    public init() {}

    public func preferredPick(stackID: UUID, albumID: UUID?, members: [Photo]) -> Photo? {
        let albumPick = albumID.flatMap { albumPicks[$0]?[stackID] }
        return members.first { $0.id == albumPick }
            ?? members.first { $0.id == picks[stackID] }
            ?? members.first
    }

    /// Filters are applied before resolving covers, so a matching stack member stays visible.
    public func presenting(_ photos: [Photo], albumID: UUID?) -> [Photo] {
        guard !collapsed.isEmpty else { return photos }
        var groups: [UUID: [Photo]] = [:]
        for photo in photos {
            if let stackID = photo.stackID, collapsed.contains(stackID) {
                groups[stackID, default: []].append(photo)
            }
        }
        var emitted: Set<UUID> = []
        return photos.compactMap { photo in
            guard let stackID = photo.stackID, let members = groups[stackID] else { return photo }
            guard emitted.insert(stackID).inserted else { return nil }
            return preferredPick(stackID: stackID, albumID: albumID, members: members)
        }
    }

    public mutating func setCollapsed(_ value: Bool, stackID: UUID) {
        if value { collapsed.insert(stackID) }
        else { collapsed.remove(stackID) }
    }

    mutating func discardEmptiedTrash(photoIDs: Set<UUID>, stackIDs: Set<UUID>) {
        collapsed.subtract(stackIDs)
        picks = picks.filter { !stackIDs.contains($0.key) && !photoIDs.contains($0.value) }
        albumPicks = albumPicks.compactMapValues { album in
            let surviving = album.filter { !stackIDs.contains($0.key) && !photoIDs.contains($0.value) }
            return surviving.isEmpty ? nil : surviving
        }
    }

    mutating func apply(_ change: StackPickChange) -> StackPickChange {
        let previous: UUID?
        if let albumID = change.albumID {
            var album = albumPicks[albumID] ?? [:]
            previous = album.updateOrRemove(change.photoID, for: change.stackID)
            albumPicks[albumID] = album.isEmpty ? nil : album
        } else {
            previous = picks.updateOrRemove(change.photoID, for: change.stackID)
        }
        return StackPickChange(stackID: change.stackID, albumID: change.albumID,
                               photoID: previous, selectionID: change.selectionID)
    }
}

private extension Dictionary {
    mutating func updateOrRemove(_ value: Value?, for key: Key) -> Value? {
        if let value { return updateValue(value, forKey: key) }
        return removeValue(forKey: key)
    }
}

public extension Library {
    @discardableResult
    mutating func applyStackPick(_ change: StackPickChange) -> StackPickChange {
        var state = stackBrowser ?? StackBrowserState()
        let inverse = state.apply(change)
        stackBrowser = state
        version = max(version, 3)
        return inverse
    }

    mutating func applyStackPicks(_ changes: [StackPickChange]) {
        guard !changes.isEmpty else { return }
        var state = stackBrowser ?? StackBrowserState()
        for change in changes { _ = state.apply(change) }
        stackBrowser = state
        version = max(version, 3)
    }

    mutating func setStackCollapsed(_ value: Bool, stackID: UUID) {
        var state = stackBrowser ?? StackBrowserState()
        state.setCollapsed(value, stackID: stackID)
        stackBrowser = state
        version = max(version, 3)
    }
}
