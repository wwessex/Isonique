import SwiftUI
import AppKit
import IsoniqueCore

extension Workspace {
    private func activateLibrary(_ repo: LibraryRepository, library restored: Library) {
        if !ProcessInfo.processInfo.arguments.contains("--library") {
            var opened = [repo.root.path]
            if let previous = repository?.root.path, previous != repo.root.path { opened.append(previous) }
            let older = recentLibraryPaths.filter { !opened.contains($0) }
            recentLibraryPaths = Array((opened + older).prefix(Self.recentLibraryLimit))
            preferences.set(repo.root.path, forKey: "library.selectedRoot")
        }
        repository = repo; library = restored
        history = keepHistory ? (library.history ?? EditHistory()) : EditHistory()
        scope = "all"; search = ""; ratingFilter = .all; originalFilter = .all; colorFilter = .all; advancedSearch = nil
        batchMode = false; batchSelection = []; selection = nil
        viewer = false; tool = .select; compareOriginal = false; stopComparison(); liftedAdjustments = nil
    }

    func createLibraryPanel() {
        guard !busy else { return }
        let panel = NSSavePanel()
        panel.title = "New Isonique Library"
        panel.nameFieldStringValue = "Isonique Library"
        panel.message = "Choose a location and name for a new library folder."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            let repository = try LibraryRepository.createEmpty(at: destination)
            activateLibrary(repository, library: Library())
            status = "Created library · \(repository.root.path)"
        } catch { self.error = error.localizedDescription }
    }

    func openLibraryPanel() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = "Open Isonique Library"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "Choose an existing Isonique library folder. Its catalogue and available managed originals are checked. Missing originals can be relinked."
        guard panel.runModal() == .OK, let source = panel.url else { return }
        Task { await openLibrary(at: source) }
    }

    func openLibrary(at source: URL) async {
        guard !busy else { return }
        busy = true
        status = "Checking library before opening…"
        defer { busy = false }
        do {
            let (repository, opened) = try await Task.detached { try LibraryBackup.openVerified(source) }.value
            activateLibrary(repository, library: opened)
            status = "Opened library · \(repository.root.path)"
        } catch {
            self.error = error.localizedDescription
            status = "Could not open library"
        }
    }

    func recentLibraryTitle(for path: String) -> String {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let name = url.lastPathComponent
        if recentLibraryPaths.contains(where: { $0 != path && URL(fileURLWithPath: $0).lastPathComponent == name }) {
            return "\(name) — \(url.deletingLastPathComponent().path)"
        }
        return name
    }

    var selectedProjectForExport: Collection? {
        library.projects.first { scope == "project:\($0.id)" }
    }

    func exportProjectPanel(_ project: Collection) {
        guard repository != nil, !busy else { return }
        let panel = NSSavePanel()
        panel.title = "Export Project as Library"
        panel.prompt = "Export Library"
        panel.nameFieldStringValue = project.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.message = "Choose a new folder for the active photos in \(project.name). The exported library contains copies of all originals, including referenced files."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        Task { await exportProject(project.id, to: destination) }
    }

    func exportProject(_ projectID: UUID, to destination: URL) async {
        guard let repository, !busy else { return }
        busy = true
        status = "Copying and verifying project originals…"
        let task = Task.detached(priority: .utility) {
            try LibraryBackup.exportProject(projectID, from: repository, to: destination)
        }
        projectExportTask = task
        defer { projectExportTask = nil; busy = false }
        do {
            let count = try await task.value
            status = "Exported project library · \(count) photos · \(destination.path)"
        } catch is CancellationError {
            status = "Project export cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "Project export failed"
        }
    }

    func importProjectLibraryPanel() {
        guard repository != nil, !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Import Project Library"
        panel.prompt = "Import Project"
        panel.message = "Choose a folder created by Export Project as Library. Its photos and originals will be copied into a separate project in the current library."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let source = panel.url else { return }
        Task { await importProjectLibrary(from: source) }
    }

    func importProjectLibrary(from source: URL) async {
        guard let repository, !busy else { return }
        busy = true
        status = "Checking project library…"
        let reservedHistory = history
        let task = Task.detached(priority: .utility) {
            try await repository.importProjectLibrary(from: source, reserving: reservedHistory) { progress in
                await self.reportProjectImportProgress(progress)
            }
        }
        projectImportTask = task
        defer { projectImportTask = nil; busy = false }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            showProjectTransfer(result.library, project: result.project)
            status = "Imported project · \(result.project.name) · \(result.photoCount) photos"
        } catch is CancellationError {
            status = "Project import cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "Project import failed"
        }
    }

    private func reportProjectImportProgress(_ progress: ImportProgress) {
        guard projectImportTask?.isCancelled == false || projectMergeTask?.isCancelled == false else { return }
        status = "Verified \(progress.processed) of \(progress.total) project originals…"
    }

    func cancelProjectImport() {
        guard let task = projectImportTask, !task.isCancelled else { return }
        task.cancel()
        status = "Cancelling project import…"
    }

    func mergeProjectLibraryPanel() {
        guard repository != nil, !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Merge Project Library"
        panel.prompt = "Merge Project"
        panel.message = "Choose an edited project export. Isonique finds the matching project by its saved ID and adds new photos and versions."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        let preference = NSPopUpButton()
        preference.addItems(withTitles: ["Keep current edits and memberships", "Use imported edits and memberships"])
        preference.setAccessibilityLabel("Matching photos")
        let applyTrash = NSButton(checkboxWithTitle: "Move matching photos marked as Trash into Library Trash", target: nil, action: nil)
        let choice = NSStackView(views: [NSTextField(labelWithString: "Matching photos"), preference])
        choice.spacing = 8
        let accessory = NSStackView(views: [choice, applyTrash])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let policy: ProjectMergePreference = preference.indexOfSelectedItem == 1 ? .incoming : .current
        let includeTrash = applyTrash.state == .on
        Task { await mergeProjectLibrary(from: source, prefer: policy, applyTrash: includeTrash) }
    }

    func mergeProjectLibrary(from source: URL, prefer preference: ProjectMergePreference, applyTrash: Bool) async {
        guard let repository, !busy else { return }
        busy = true
        status = "Checking project library for merge…"
        let task = Task.detached(priority: .utility) {
            try await repository.mergeProjectLibrary(from: source, prefer: preference, applyTrash: applyTrash) { progress in
                await self.reportProjectImportProgress(progress)
            }
        }
        projectMergeTask = task
        defer { projectMergeTask = nil; busy = false }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            showProjectTransfer(result.library, project: result.project)
            status = "Merged \(result.project.name) · \(result.added) added · \(result.updated) updated · \(result.trashed) trashed · \(result.skipped) skipped"
        } catch is CancellationError {
            status = "Project merge cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "Project merge failed"
        }
    }

    private func showProjectTransfer(_ saved: Library, project: Collection) {
        library = saved
        batchMode = false
        batchSelection = []
        showBrowser(allPhotos: true)
        scope = "project:\(project.id)"
        selection = photos.first?.id
    }

    func cancelProjectMerge() {
        guard let task = projectMergeTask, !task.isCancelled else { return }
        task.cancel()
        status = "Cancelling project merge…"
    }

    func verifyLibrary() {
        guard let repository, !busy else { return }
        busy = true; status = "Checking catalogue and original hashes…"
        Task {
            do {
                let count = try await Task.detached { try LibraryBackup.verify(repository) }.value
                status = "Library verified · \(count) originals match their saved hashes"
            } catch { self.error = error.localizedDescription; status = "Library check failed" }
            busy = false
        }
    }

    func backupLibraryPanel() {
        guard let repository, !busy else { return }
        let panel = NSSavePanel(); panel.title = "Back Up Isonique Library"
        panel.nameFieldStringValue = "Isonique Backup \(Date().formatted(.iso8601.year().month().day()))"
        panel.message = "Choose a new folder, preferably on another drive. Includes the catalogue, edits and managed originals. Referenced originals stay in their external locations and need their own backup."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true; status = "Copying and verifying library backup…"
        Task {
            do {
                try await Task.detached { try LibraryBackup.create(from: repository, to: destination) }.value
                status = "Verified backup saved · \(destination.path)"
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch { self.error = error.localizedDescription; status = "Backup failed" }
            busy = false
        }
    }

    func restoreLibraryPanel() {
        guard !busy else { return }
        let sourcePanel = NSOpenPanel(); sourcePanel.title = "Choose an Isonique Backup"
        sourcePanel.canChooseFiles = false; sourcePanel.canChooseDirectories = true
        sourcePanel.message = "Select a backup made with Back Up Library. Aperture libraries use Recover Aperture Originals instead."
        guard sourcePanel.runModal() == .OK, let source = sourcePanel.url else { return }
        busy = true; status = "Checking backup before choosing a restore location…"
        Task {
            defer { busy = false }
            do {
                let count = try await Task.detached { try LibraryBackup.validateBackup(source) }.value
                try await restoreValidatedBackup(source, count: count)
            } catch { self.error = error.localizedDescription; status = "Restore failed · current library unchanged" }
        }
    }

    private func restoreValidatedBackup(_ source: URL, count: Int) async throws {
        let panel = NSSavePanel(); panel.title = "Restore Library into a New Folder"
        panel.nameFieldStringValue = "Isonique Restored Library"
        panel.message = "Backup checked: \(count) photos. Choose a new folder. The restored library opens here and on future launches. Your current library and backup remain intact."
        guard panel.runModal() == .OK, let destination = panel.url else {
            status = "Restore cancelled · current library unchanged"
            return
        }
        let current = repository?.root
        status = "Restoring and verifying library…"
        let restored = try await Task.detached { () -> (LibraryRepository, Library) in
            try LibraryBackup.restore(from: source, to: destination, excluding: current)
            let repo = try LibraryRepository(root: destination)
            return (repo, try repo.load())
        }.value
        activateLibrary(restored.0, library: restored.1)
        status = "Restored and verified \(library.photos.count) photos · \(destination.path)"
    }
}
