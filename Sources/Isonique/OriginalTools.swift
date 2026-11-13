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

    func findOriginalsPanel(_ operation: OriginalFolderOperation, firstAid: LibraryFirstAidReport? = nil,
                            restrictedTo originalIDs: Set<UUID>? = nil) {
        guard !busy, repository != nil, originalIDs?.isEmpty != true,
              firstAid != nil || canFindOriginals(operation) else { return }
        let panel = NSOpenPanel()
        panel.title = operation.title
        panel.message = operation.prompt
        if firstAid != nil { panel.message = operation.prompt + " Recovery applies to the originals in the reviewed report." }
        if originalIDs != nil { panel.message = operation.prompt + " Only originals listed in People Review Summary will be searched." }
        panel.prompt = "Search Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        let choices = firstAid == nil && originalIDs == nil ? originalFolderScopes(for: operation) : []
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
        let selection = picker.indexOfSelectedItem
        let targets = originalIDs ?? (choices.indices.contains(selection) ? choices[selection].originalIDs : nil)
        Task { await findOriginals(in: folder, operation: operation, originalIDs: targets, firstAid: firstAid) }
    }

    @discardableResult
    func findOriginals(in folder: URL, operation: OriginalFolderOperation, originalIDs: Set<UUID>? = nil,
                       firstAid: LibraryFirstAidReport? = nil, presentResultInWorkspace: Bool = true) async -> String? {
        guard originalIDs?.isEmpty != true, firstAid != nil || canFindOriginals(operation) else { return nil }
        return await runOriginalJob(status: "Searching for missing originals…",
                                    presentResultInWorkspace: presentResultInWorkspace) { repository, current in
            switch operation {
            case .reconnect:
                var draft = current
                let report: OriginalReconnectReport
                if let firstAid {
                    (draft, report) = try repository.reconnectOfflineReferences(in: folder, after: firstAid, basedOn: current)
                } else {
                    report = try repository.reconnectMissingReferences(in: folder, library: &draft, originalIDs: originalIDs)
                }
                let summary = report.reconnected.isEmpty && report.unmatched.isEmpty && report.ambiguous.isEmpty
                    ? "No missing referenced originals"
                    : "\(report.reconnected.count) reconnected · \(report.unmatched.count) unmatched · \(report.ambiguous.count) ambiguous"
                return (report.reconnected.isEmpty ? nil : draft, OriginalJobResult(
                    title: operation.title, summary: summary, unmatched: report.unmatched, ambiguous: report.ambiguous,
                    scanErrors: report.scanErrors))
            case .recoverManaged:
                let report: ManagedOriginalRecoveryReport
                if let firstAid {
                    report = try repository.recoverMissingManagedOriginals(in: folder, after: firstAid)
                } else {
                    report = try repository.recoverMissingManagedOriginals(in: folder, library: current, originalIDs: originalIDs)
                }
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

    var relocationHasReferencedOriginals: Bool {
        !selectedOriginalIDs(matching: OriginalFolderOperation.reconnect.includes).isEmpty
    }

    func relocateSelectedOriginalsPanel() {
        guard canRelocateSelectedOriginals else { return }
        pendingRelocationOptions = nil
        showRelocationOptions = true
    }

    func chooseRelocationDestination() {
        let pending = pendingRelocationOptions
        pendingRelocationOptions = nil
        guard let options = pending, canRelocateSelectedOriginals else { return }
        let ids = selectedOriginalIDs { $0.trashedAt == nil }
        let panel = NSOpenPanel()
        panel.title = "Relocate Originals"
        panel.message = "Choose a folder outside this library to preview the relocation."
        panel.prompt = "Preview"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task { await reviewRelocation(ids, to: folder, options: options) }
    }

    private func reviewRelocation(_ ids: Set<UUID>, to folder: URL, options: OriginalRelocationOptions) async {
        guard !busy, let repository else { return }
        let current = library
        busy = true
        status = "Preparing relocation preview…"
        let preview: OriginalRelocationPreview
        do {
            preview = try await Task.detached(priority: .utility) {
                try repository.previewRelocatingOriginals(ids, to: folder, in: current, options: options)
            }.value
        } catch {
            busy = false
            self.error = error.localizedDescription
            status = "Could not preview relocation"
            return
        }
        let approved = presentRelocationPreview(preview, options: options)
        busy = false
        guard approved else { status = "Relocation preview closed"; return }
        await relocateOriginals(after: preview)
    }

    private func presentRelocationPreview(_ preview: OriginalRelocationPreview, options: OriginalRelocationOptions) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Preview Relocate Originals"
        let items = preview.items
        let ready = preview.relocationCount
        let skipped = items.count - ready
        let action = options.keepReferencedSources ? "Previous referenced copies will be kept."
            : "Previous referenced copies still used by the catalogue will be kept."
        let preset = options.customPreset.map { "Preset: \($0.name)\n" } ?? ""
        alert.informativeText = "\(ready) to relocate · \(skipped) skipped\n\(preview.destination.path)\n" + preset + "\n"
            + "Isonique verifies the destination copies and saves their paths before sending eligible old files to Finder Trash. " + action
        let scroll = NSTextView.scrollableTextView()
        scroll.frame.size = NSSize(width: 480, height: min(265, max(70, items.count * 43)))
        if let text = scroll.documentView as? NSTextView {
            text.string = items.map { item in
                let versions = item.versionCount > 1 ? " (\(item.versionCount) versions)" : ""
                let relative = item.destinationPath ?? item.preferredPath
                let outcome: String
                switch item.disposition {
                case .copy: outcome = relative == item.preferredPath ? "Copy" : "Copy using storage name (collision)"
                case .reuse: outcome = relative == item.preferredPath ? "Reuse verified copy" : "Reuse verified copy under storage name"
                case .alreadyThere: outcome = "Already at destination"
                case .unavailable: outcome = "Original unavailable"
                case .occupied: outcome = "Destination unavailable"
                }
                return "\(item.originalName)\(versions)\n\(outcome): \(relative)"
            }.joined(separator: "\n\n")
            text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            text.isEditable = false
            text.setAccessibilityLabel("Relocation preview paths")
        }
        alert.accessoryView = scroll
        alert.addButton(withTitle: ready == 0 ? "Done" : "Cancel")
        if ready > 0 { alert.addButton(withTitle: "Relocate Originals").keyEquivalent = "" }
        return alert.runModal() == .alertSecondButtonReturn && ready > 0
    }

    private func relocateOriginals(after preview: OriginalRelocationPreview) async {
        await runOriginalJob(status: "Copying and verifying originals for relocation…") { repository, current in
            var draft = current
            let report = try repository.relocateOriginals(after: preview, in: &draft)
            let summary = "\(report.relocated.count) relocated · \(report.unavailable.count) unavailable"
            return (report.relocated.isEmpty ? nil : draft, OriginalJobResult(
                title: "Relocate Originals", summary: summary, unavailable: report.unavailable,
                occupied: report.occupied, failed: report.failed, renamed: report.renamed, retained: report.retained,
                alreadyInFolder: report.alreadyInFolder))
        }
    }

    @discardableResult
    private func runOriginalJob(status pending: String, presentResultInWorkspace: Bool = true,
                                operation: @escaping @Sendable (LibraryRepository, Library) throws -> (Library?, OriginalJobResult)) async -> String? {
        guard !busy, let repository else { return nil }
        guard !Task.isCancelled else { return String(localized: "Original operation cancelled") }
        let current = library
        busy = true
        status = pending
        let task = Task.detached(priority: .utility) { try operation(repository, current) }
        originalJobTask = task
        defer { originalJobTask = nil; busy = false }
        do {
            let (draft, result) = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if let draft { library = draft }
            let preferred = selection
            refreshOriginalStatus()
            if selected == nil { selectAfterChange(preferred: preferred) }
            if presentResultInWorkspace { originalJobResult = result }
            status = result.summary
            return result.details
        } catch is CancellationError {
            status = "Original operation cancelled"
            return status
        } catch {
            if presentResultInWorkspace { self.error = error.localizedDescription }
            status = "Original operation failed"
            return error.localizedDescription
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
                      ("Saved under another name", renamed), ("Old file retained", retained), ("Already at destination", alreadyInFolder)]
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
