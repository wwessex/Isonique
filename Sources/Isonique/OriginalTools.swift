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
        !busy && repository != nil && library.photos.contains(where: operation.includes)
    }

    private func selectedOriginalIDs(matching includes: (Photo) -> Bool) -> Set<UUID> {
        let selectionIDs = batchMode ? batchSelection : Set(selection.map { [$0] } ?? [])
        guard !selectionIDs.isEmpty else { return [] }
        return Set(photos.filter { selectionIDs.contains($0.id) && includes($0) }.map(\.originalID))
    }

    func originalFolderScopes(for operation: OriginalFolderOperation) -> [OriginalFolderScope] {
        var choices = [OriginalFolderScope(title: "Entire Library", originalIDs: nil)]
        let selectedOriginals = selectedOriginalIDs(matching: operation.includes)
        if !selectedOriginals.isEmpty {
            choices.append(OriginalFolderScope(title: "Selected Photos", originalIDs: selectedOriginals))
        }
        if let project = library.projects.first(where: { scope == "project:\($0.id)" }) {
            let projectOriginals = Set(library.activePhotos.filter { $0.projectID == project.id && operation.includes($0) }.map(\.originalID))
            if !projectOriginals.isEmpty {
                choices.append(OriginalFolderScope(title: "Current Project", originalIDs: projectOriginals))
            }
        }
        return choices
    }

    func findOriginalsPanel(_ operation: OriginalFolderOperation) {
        guard canFindOriginals(operation) else { return }
        let panel = NSOpenPanel()
        panel.title = operation.title
        panel.message = operation.prompt
        panel.prompt = "Search Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        let choices = originalFolderScopes(for: operation)
        let picker = NSPopUpButton()
        picker.addItems(withTitles: choices.map(\.title))
        picker.setAccessibilityLabel("Apply to")
        if choices.count > 1 {
            let accessory = NSStackView(views: [NSTextField(labelWithString: "Apply to"), picker])
            accessory.spacing = 8
            accessory.frame.size = accessory.fittingSize
            panel.accessoryView = accessory
            panel.isAccessoryViewDisclosed = true
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let originalIDs = choices[picker.indexOfSelectedItem].originalIDs
        Task { await findOriginals(in: folder, operation: operation, originalIDs: originalIDs) }
    }

    func findOriginals(in folder: URL, operation: OriginalFolderOperation, originalIDs: Set<UUID>? = nil) async {
        guard canFindOriginals(operation) else { return }
        await runOriginalJob(status: "Searching for missing originals…") { repository, current in
            switch operation {
            case .reconnect:
                var draft = current
                let report = try repository.reconnectMissingReferences(in: folder, library: &draft, originalIDs: originalIDs)
                let summary = report.reconnected.isEmpty && report.unmatched.isEmpty && report.ambiguous.isEmpty
                    ? "No missing referenced originals"
                    : "\(report.reconnected.count) reconnected · \(report.unmatched.count) unmatched · \(report.ambiguous.count) ambiguous"
                return (report.reconnected.isEmpty ? nil : draft, OriginalJobResult(
                    title: operation.title, summary: summary, unmatched: report.unmatched, ambiguous: report.ambiguous,
                    scanErrors: report.scanErrors))
            case .recoverManaged:
                let report = try repository.recoverMissingManagedOriginals(in: folder, library: current, originalIDs: originalIDs)
                let summary = report.restored.isEmpty && report.unmatched.isEmpty && report.ambiguous.isEmpty &&
                    report.occupied.isEmpty && report.failed.isEmpty && !report.cancelled
                    ? "No missing managed originals"
                    : "\(report.restored.count) restored · \(report.unmatched.count) unmatched · \(report.ambiguous.count) ambiguous"
                return (nil, OriginalJobResult(
                    title: operation.title, summary: summary, unmatched: report.unmatched, ambiguous: report.ambiguous,
                    occupied: report.occupied, failed: report.failed, scanErrors: report.scanErrors,
                    cancelled: report.cancelled))
            }
        }
    }

    var canConsolidateSelectedOriginals: Bool {
        !busy && repository != nil && batchMode && !isViewingTrash && !selectedOriginalIDs(matching: OriginalFolderOperation.reconnect.includes).isEmpty
    }

    func consolidateSelectedOriginals() async {
        guard canConsolidateSelectedOriginals else { return }
        let ids = selectedOriginalIDs(matching: OriginalFolderOperation.reconnect.includes)
        await runOriginalJob(status: "Copying and verifying selected originals…") { repository, current in
            var draft = current
            let report = try repository.consolidateOriginals(ids, in: &draft)
            let summary = "\(report.consolidated.count) consolidated · \(report.unavailable.count) unavailable"
            return (report.consolidated.isEmpty ? nil : draft, OriginalJobResult(
                title: "Consolidate Selected Originals", summary: summary, unavailable: report.unavailable,
                occupied: report.occupied, failed: report.failed, cancelled: report.cancelled))
        }
    }

    var canRelocateSelectedOriginals: Bool {
        !busy && repository != nil && !isViewingTrash && !selectedOriginalIDs { $0.trashedAt == nil }.isEmpty
    }

    func relocateSelectedOriginalsPanel() {
        guard canRelocateSelectedOriginals else { return }
        let ids = selectedOriginalIDs { $0.trashedAt == nil }
        let panel = NSOpenPanel()
        panel.title = "Relocate Originals"
        panel.message = "Choose a folder outside this library. Isonique verifies the copies and saves their new references before sending eligible old files to Finder Trash."
        panel.prompt = "Relocate Originals"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        let keepReferences = NSButton(checkboxWithTitle: "Keep copies at previous referenced locations", target: nil, action: nil)
        keepReferences.state = .on
        if !selectedOriginalIDs(matching: OriginalFolderOperation.reconnect.includes).isEmpty {
            keepReferences.frame.size = keepReferences.fittingSize
            panel.accessoryView = keepReferences
            panel.isAccessoryViewDisclosed = true
        }
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let keepReferencedSources = keepReferences.state == .on
        Task { await relocateOriginals(ids, to: folder, keepReferencedSources: keepReferencedSources) }
    }

    func relocateOriginals(_ ids: Set<UUID>, to folder: URL, keepReferencedSources: Bool) async {
        await runOriginalJob(status: "Copying and verifying originals for relocation…") { repository, current in
            var draft = current
            let report = try repository.relocateOriginals(ids, to: folder, in: &draft, keepReferencedSources: keepReferencedSources)
            let summary = "\(report.relocated.count) relocated · \(report.unavailable.count) unavailable"
            return (report.relocated.isEmpty ? nil : draft, OriginalJobResult(
                title: "Relocate Originals", summary: summary, unavailable: report.unavailable,
                occupied: report.occupied, failed: report.failed, renamed: report.renamed, retained: report.retained,
                alreadyInFolder: report.alreadyInFolder))
        }
    }

    private func runOriginalJob(status pending: String,
                                operation: @escaping @Sendable (LibraryRepository, Library) throws -> (Library?, OriginalJobResult)) async {
        guard !busy, let repository else { return }
        let current = library
        busy = true
        status = pending
        let task = Task.detached(priority: .utility) { try operation(repository, current) }
        originalJobTask = task
        defer { originalJobTask = nil; busy = false }
        do {
            let (draft, result) = try await task.value
            if let draft { library = draft }
            let preferred = selection
            refreshOriginalStatus()
            if selected == nil { selectAfterChange(preferred: preferred) }
            originalJobResult = result
            status = result.summary
        } catch is CancellationError {
            status = "Original operation cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "Original operation failed"
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

    func includes(_ photo: Photo) -> Bool {
        switch self {
        case .reconnect: return photo.trashedAt == nil && photo.referencedPath != nil
        case .recoverManaged: return photo.referencedPath == nil
        }
    }

    var title: String {
        switch self {
        case .reconnect: return "Reconnect Referenced Originals"
        case .recoverManaged: return "Recover Missing Managed Originals"
        }
    }

    var prompt: String {
        switch self {
        case .reconnect:
            return "Choose a folder to search for missing referenced originals. Isonique checks known filenames and verifies each match against the original fingerprint."
        case .recoverManaged:
            return "Choose a backup or folder containing the missing originals. Isonique checks known filenames and copies verified matches into the library."
        }
    }
}

struct OriginalFolderScope {
    let title: String
    let originalIDs: Set<UUID>?
}

struct OriginalJobResult: Sendable {
    let title: String
    let summary: String
    var unmatched: [String] = []
    var ambiguous: [String] = []
    var unavailable: [String] = []
    var occupied: [String] = []
    var failed: [String] = []
    var renamed: [String] = []
    var retained: [String] = []
    var alreadyInFolder: [String] = []
    var scanErrors = 0
    var cancelled = false

    var details: String {
        var lines = [summary]
        let groups = [("Unmatched", unmatched), ("Multiple verified copies", ambiguous),
                      ("Original unavailable", unavailable), ("Destination unavailable", occupied), ("Operation failed for", failed),
                      ("Saved under another name", renamed), ("Old file retained", retained), ("Already in this folder", alreadyInFolder)]
        for (label, names) in groups where !names.isEmpty {
            let first = names.prefix(4).joined(separator: ", ")
            lines.append("\(label) — \(first)" + (names.count > 4 ? " and \(names.count - 4) more" : ""))
        }
        if scanErrors > 0 { lines.append("Skipped \(scanErrors) locations or files after a read error.") }
        if cancelled { lines.append("Operation cancelled. Completed copies remain in the library.") }
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
