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
