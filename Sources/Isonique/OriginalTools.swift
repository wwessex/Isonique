import SwiftUI
import AppKit
import IsoniqueCore

enum OriginalFilter: String, CaseIterable, Identifiable {
    case all = "All originals"
    case managed = "Managed originals"
    case referenced = "Referenced originals"
    case unavailable = "Unavailable originals"
    var id: Self { self }

    func includes(_ photo: Photo, repository: LibraryRepository?) -> Bool {
        switch self {
        case .all: return true
        case .managed: return photo.referencedPath == nil
        case .referenced: return photo.referencedPath != nil
        case .unavailable: return (try? repository?.availableOriginalURL(photo)) == nil
        }
    }
}

extension Workspace {
    var canRelinkSelectedOriginal: Bool {
        guard let photo = selected, let repository else { return false }
        return photo.referencedPath != nil || (try? repository.availableOriginalURL(photo)) == nil
    }

    func refreshOriginalStatus() {
        originalStatusRevision &+= 1
        if originalFilter == .unavailable, selected == nil { selection = photos.first?.id }
    }

    func relinkOriginalPanel(_ photo: Photo) {
        guard !busy, !isViewingTrash else { return }
        let panel = NSOpenPanel()
        panel.title = "Relink Original"
        panel.message = "Choose the original file for \(photo.originalName). Its contents must match the saved fingerprint."
        if let repository, let old = try? repository.originalURL(photo) {
            let parent = old.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) { panel.directoryURL = parent }
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        updateOriginal(photo, status: "Relinking original…", success: "Original relinked") { repo, library in
            try repo.relinkOriginal(photo.id, to: url, in: &library)
        }
    }

    func consolidateOriginal(_ photo: Photo) {
        updateOriginal(photo, status: "Copying and verifying original…", success: "Original consolidated · external file kept") { repo, library in
            try repo.consolidateOriginal(photo.id, in: &library)
        }
    }

    private func updateOriginal(_ photo: Photo, status pending: String, success: String,
                                operation: @escaping (LibraryRepository, inout Library) throws -> Void) {
        guard !busy, !isViewingTrash, let repository else { return }
        let current = library
        busy = true
        status = pending
        Task {
            defer { busy = false }
            do {
                library = try await Task.detached {
                    var draft = current
                    try operation(repository, &draft)
                    return draft
                }.value
                refreshOriginalStatus()
                selectAfterChange(preferred: photo.id)
                status = success
            } catch {
                self.error = error.localizedDescription
                status = "Original update failed"
            }
        }
    }
}

struct MissingOriginalView: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo

    var body: some View {
        ContentUnavailableView {
            Label("Original unavailable", systemImage: "exclamationmark.triangle")
        } description: {
            Text("Reconnect the drive or locate the original for \(photo.originalName).")
        } actions: {
            if !model.isViewingTrash {
                Button("Relink Original…") { model.relinkOriginalPanel(photo) }
            }
            Button("Refresh", action: model.refreshOriginalStatus)
        }
    }
}

struct OriginalInfoView: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo

    var body: some View {
        let url = try? model.repository?.availableOriginalURL(photo)
        let referenced = photo.referencedPath != nil
        LabeledContent("Original storage", value: referenced ? "Referenced" : "Managed")
        if let path = photo.referencedPath {
            Text(path).lineLimit(2).truncationMode(.middle).textSelection(.enabled)
                .foregroundStyle(.secondary)
        }
        if let url {
            Button("Reveal Original in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        } else {
            Label("Original unavailable", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
        if referenced || url == nil {
            Button("Relink Original…") { model.relinkOriginalPanel(photo) }
        }
        if referenced, url != nil {
            Button("Consolidate Original") { model.consolidateOriginal(photo) }
            Text("Copies this original into the library and keeps the external file.").foregroundStyle(.secondary)
        }
    }
}
