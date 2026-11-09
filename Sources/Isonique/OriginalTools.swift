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

    func canFindOriginals(_ operation: OriginalFolderOperation) -> Bool {
        !busy && repository != nil && library.photos.contains { photo in
            switch operation {
            case .reconnect: return photo.trashedAt == nil && photo.referencedPath != nil
            case .recoverManaged: return photo.referencedPath == nil
            }
        }
    }

    func findOriginalsPanel(_ operation: OriginalFolderOperation) {
        guard canFindOriginals(operation) else { return }
        let panel = NSOpenPanel()
        panel.title = operation.title
        panel.message = operation.prompt
        panel.prompt = "Search Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { await findOriginals(in: folder, operation: operation) }
    }

    func findOriginals(in folder: URL, operation: OriginalFolderOperation) async {
        guard canFindOriginals(operation), let repository else { return }
        let current = library
        busy = true
        status = "Searching for missing originals…"
        let task = Task.detached(priority: .utility) { () throws -> (Library?, OriginalFolderResult) in
            switch operation {
            case .reconnect:
                var draft = current
                let report = try repository.reconnectMissingReferences(in: folder, library: &draft)
                let summary = report.reconnected.isEmpty && report.unmatched.isEmpty && report.ambiguous.isEmpty
                    ? "No missing referenced originals"
                    : "\(report.reconnected.count) reconnected · \(report.unmatched.count) unmatched · \(report.ambiguous.count) ambiguous"
                return (report.reconnected.isEmpty ? nil : draft, OriginalFolderResult(
                    title: operation.title, summary: summary, unmatched: report.unmatched, ambiguous: report.ambiguous,
                    scanErrors: report.scanErrors))
            case .recoverManaged:
                let report = try repository.recoverMissingManagedOriginals(in: folder, library: current)
                let summary = report.restored.isEmpty && report.unmatched.isEmpty && report.ambiguous.isEmpty &&
                    report.occupied.isEmpty && report.failed.isEmpty && !report.cancelled
                    ? "No missing managed originals"
                    : "\(report.restored.count) restored · \(report.unmatched.count) unmatched · \(report.ambiguous.count) ambiguous"
                return (nil, OriginalFolderResult(
                    title: operation.title, summary: summary, unmatched: report.unmatched, ambiguous: report.ambiguous,
                    occupied: report.occupied, failed: report.failed, scanErrors: report.scanErrors,
                    cancelled: report.cancelled))
            }
        }
        originalFolderTask = task
        defer { originalFolderTask = nil; busy = false }
        do {
            let (draft, result) = try await task.value
            if let draft { library = draft }
            let preferred = selection
            refreshOriginalStatus()
            if selected == nil { selectAfterChange(preferred: preferred) }
            originalFolderResult = result
            status = result.summary
        } catch is CancellationError {
            status = "Original search cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "Original search failed"
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

enum OriginalFolderOperation: Sendable {
    case reconnect, recoverManaged

    var title: String {
        switch self {
        case .reconnect: return "Reconnect Referenced Originals"
        case .recoverManaged: return "Recover Missing Managed Originals"
        }
    }

    var prompt: String {
        switch self {
        case .reconnect:
            return "Choose a folder to search for missing referenced originals in this library. Isonique checks known filenames and verifies each match against the original fingerprint."
        case .recoverManaged:
            return "Choose a backup or folder containing the missing originals. Isonique checks known filenames and copies verified matches into the library."
        }
    }
}

struct OriginalFolderResult: Sendable {
    let title: String
    let summary: String
    let unmatched: [String]
    let ambiguous: [String]
    var occupied: [String] = []
    var failed: [String] = []
    let scanErrors: Int
    var cancelled = false

    var details: String {
        var lines = [summary]
        let groups = [("Unmatched", unmatched), ("Multiple verified copies", ambiguous),
                      ("Destination unavailable", occupied), ("Could not restore", failed)]
        for (label, names) in groups where !names.isEmpty {
            let first = names.prefix(4).joined(separator: ", ")
            lines.append("\(label) — \(first)" + (names.count > 4 ? " and \(names.count - 4) more" : ""))
        }
        if scanErrors > 0 { lines.append("Skipped \(scanErrors) locations or files after a read error.") }
        if cancelled { lines.append("Recovery cancelled. Completed copies remain in the library.") }
        return lines.joined(separator: "\n")
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
