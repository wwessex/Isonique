import SwiftUI
import IsoniqueCore

extension Workspace {
    var isViewingStack: Bool { scope.hasPrefix("stack:") }

    var currentAlbumID: UUID? {
        guard scope.hasPrefix("album:") else { return nil }
        return UUID(uuidString: String(scope.dropFirst(6)))
    }

    var activeStacks: [UUID: [Photo]] {
        var result: [UUID: [Photo]] = [:]
        for photo in library.photos where photo.trashedAt == nil {
            if let stackID = photo.stackID { result[stackID, default: []].append(photo) }
        }
        return result
    }

    var canSetStackPick: Bool {
        guard let photo = selected else { return false }
        return canSetPick(for: photo)
    }

    var canSetAlbumPick: Bool {
        guard let photo = selected else { return false }
        return canSetPick(for: photo, inAlbum: true)
    }

    func canSetPick(for photo: Photo, inAlbum: Bool = false) -> Bool {
        guard !busy, !batchMode, photo.trashedAt == nil, let stackID = photo.stackID else { return false }
        if inAlbum {
            guard let albumID = currentAlbumID, photo.albumIDs.contains(albumID) else { return false }
            return library.photos.contains {
                $0.id != photo.id && $0.trashedAt == nil && $0.stackID == stackID && $0.albumIDs.contains(albumID)
            }
        }
        return library.photos.contains { $0.id != photo.id && $0.trashedAt == nil && $0.stackID == stackID }
    }

    var selectedIsAlbumPick: Bool { selected.map(isAlbumPick) ?? false }

    func isAlbumPick(_ photo: Photo) -> Bool {
        guard let albumID = currentAlbumID, let stackID = photo.stackID else { return false }
        return library.stackBrowser?.albumPicks[albumID]?[stackID] == photo.id
    }

    var selectedStackIsCollapsed: Bool {
        selected?.stackID.map(isStackCollapsed) ?? false
    }

    var canToggleSelectedStack: Bool {
        guard let photo = selected else { return false }
        return canSetPick(for: photo) && !isViewingStack
    }

    func isStackCollapsed(_ id: UUID) -> Bool {
        !isViewingStack && !isViewingTrash && library.stackBrowser?.collapsed.contains(id) == true
    }

    func setStackPick(_ target: Photo? = nil, inAlbum: Bool = false) {
        guard let photo = target ?? selected, canSetPick(for: photo, inAlbum: inAlbum),
              let stackID = photo.stackID else { return }
        let album = inAlbum ? currentAlbumID : nil
        let clear = inAlbum && isAlbumPick(photo)
        let change = StackPickChange(stackID: stackID, albumID: album, photoID: clear ? nil : photo.id, selectionID: photo.id)
        var draft = library
        let inverse = draft.applyStackPick(change)
        guard inverse.photoID != change.photoID else { return }
        var nextHistory = history
        nextHistory.record(.stackPick(inverse))
        guard commit(draft, history: nextHistory) else { return }
        selectAfterChange(preferred: photo.id)
        status = clear ? "Album pick cleared" : (inAlbum ? "Album pick set" : "Stack pick set")
    }

    func toggleStack(_ id: UUID) {
        guard !busy, !batchMode, !isViewingTrash, !isViewingStack,
              (activeStacks[id]?.count ?? 0) > 1 else { return }
        var draft = library
        let collapse = !isStackCollapsed(id)
        draft.setStackCollapsed(collapse, stackID: id)
        guard commit(draft) else { return }
        selectAfterChange(preferred: selection)
        status = collapse ? "Stack collapsed" : "Stack expanded"
    }
}

struct StackBadge: View {
    @EnvironmentObject var model: Workspace
    let stackID: UUID
    let photoID: UUID

    var body: some View {
        let albumPick = model.currentAlbumID.flatMap { model.library.stackBrowser?.albumPicks[$0]?[stackID] } == photoID
        let stackPick = model.library.stackBrowser?.picks[stackID] == photoID
        let collapsed = model.isStackCollapsed(stackID)
        HStack(spacing: 3) {
            Image(systemName: albumPick ? "bookmark.fill" : (stackPick ? "star.circle.fill" : "square.3.layers.3d"))
                .foregroundStyle(albumPick || stackPick ? Color.accentColor : Color.secondary)
            if collapsed { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel((albumPick ? "Album pick" : (stackPick ? "Stack pick" : "Stack member")) +
                                (collapsed ? ", collapsed stack" : ""))
    }
}

struct StackContextActions: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo

    var body: some View {
        if let stackID = photo.stackID, model.canSetPick(for: photo) {
            Button("Set Stack Pick") { model.setStackPick(photo) }
            if model.canSetPick(for: photo, inAlbum: true) {
                Button(model.isAlbumPick(photo) ? "Clear Album Pick" : "Set Album Pick") { model.setStackPick(photo, inAlbum: true) }
            }
            if !model.isViewingStack {
                Button(model.isStackCollapsed(stackID) ? "Expand Stack" : "Collapse Stack") { model.toggleStack(stackID) }
            }
            Divider()
        }
    }
}
