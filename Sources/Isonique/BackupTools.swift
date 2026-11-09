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
        preference.addItems(withTitles: ["Prefer current values", "Prefer imported values"])
        preference.setAccessibilityLabel("Conflict preference")
        let applyTrash = NSButton(checkboxWithTitle: "Apply export deletions to Library Trash", target: nil, action: nil)
        let choice = NSStackView(views: [NSTextField(labelWithString: "Conflict preference"), preference])
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
            try await repository.mergeProjectLibrary(from: source, prefer: preference, applyTrash: applyTrash, review: { preview in
                await self.reviewProjectMerge(preview, preference: preference)
            }) { progress in
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
            let conflictLabel = result.conflicts == 1 ? "conflict" : "conflicts"
            status = "Merged \(result.project.name) · \(result.added) added · \(result.updated) updated · \(result.trashed) trashed · \(result.skipped) skipped · \(result.conflicts) \(conflictLabel)"
            if result.albumUpdates > 0 { status += " · \(albumUpdateLabel(result.albumUpdates)) updated" }
            if result.stackUpdates > 0 { status += " · \(stackUpdateLabel(result.stackUpdates)) updated" }
        } catch is CancellationError {
            status = "Project merge cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "Project merge failed"
        }
    }

    private func reviewProjectMerge(_ preview: ProjectLibraryMergePreview, preference: ProjectMergePreference) -> Bool {
        guard projectMergeTask?.isCancelled == false else { return false }
        let alert = NSAlert()
        alert.messageText = "Review Merge into \(preview.projectName)"
        var details = [
            "\(preview.added) photos to add, \(preview.updated) to update, \(preview.trashed) to move to Library Trash.",
            "\(preview.addedAlbums) albums to add, \(preview.copiedOriginals) originals to copy, \(preview.skipped) photos to skip."
        ]
        let preferred = preference == .current ? "Current values" : "Imported values"
        if preview.albumUpdates > 0 { details.append("\(albumUpdateLabel(preview.albumUpdates)) to update.") }
        if preview.stackUpdates > 0 { details.append("\(stackUpdateLabel(preview.stackUpdates)) to update.") }
        if !preview.conflicts.isEmpty {
            let subject = preview.conflicts.count == 1 ? "photo" : "photos"
            details.append("\(preferred) will resolve conflicts on \(preview.conflicts.count) \(subject).")
            details += preview.conflicts.prefix(5).map { "\($0.photoName) — \($0.fields.joined(separator: ", "))" }
        }
        if !preview.albumConflicts.isEmpty {
            details.append("\(preferred) will resolve conflicts on \(albumUpdateLabel(preview.albumConflicts.count)).")
            details += preview.albumConflicts.prefix(5).map { "\($0.albumName) — \($0.fields.joined(separator: ", "))" }
        }
        if !preview.stackConflicts.isEmpty {
            let subject = preview.stackConflicts.count == 1 ? "stack" : "stacks"
            details.append("\(preferred) will resolve conflicts on \(preview.stackConflicts.count) \(subject).")
            details += preview.stackConflicts.prefix(5).map { "Stack with \($0.representativeName) — \($0.fields.joined(separator: ", "))" }
        }
        if preview.legacyMatches > 0 {
            details.append("\(preferred) apply to \(preview.legacyMatches) matching photos without an edit baseline.")
        }
        if !preview.trashNames.isEmpty {
            let names = preview.trashNames.prefix(8).joined(separator: ", ")
            let remaining = preview.trashNames.count - min(8, preview.trashNames.count)
            details.append("Library Trash — \(names)" + (remaining > 0 ? " and \(remaining) more" : ""))
        }
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: "Merge Project")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func stackUpdateLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "stack" : "stacks")"
    }

    private func albumUpdateLabel(_ count: Int) -> String {
        "\(count) \(count == 1 ? "album" : "albums")"
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

    func mergeLibrariesPanel() {
        guard repository != nil, !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Merge Libraries"
        panel.prompt = "Review"
        panel.message = "Choose another Isonique library and how to handle matching photos. Review changes before merging."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        let choices: [(title: String, policy: LibraryMergePhotoPolicy)] = [
            ("Add new items only", .addOnly),
            ("Review differences and keep current values", .preferCurrent),
            ("Review differences and use imported values", .preferIncoming)
        ]
        let policyPicker = NSPopUpButton()
        policyPicker.addItems(withTitles: choices.map(\.title))
        policyPicker.setAccessibilityLabel("Matching photo policy")
        let policyRow = NSStackView(views: [NSTextField(labelWithString: "Matching photos"), policyPicker])
        policyRow.spacing = 8
        let trashOption = NSButton(checkboxWithTitle: "Apply source Library Trash to matching photos", target: nil, action: nil)
        trashOption.state = .off
        let accessory = NSStackView(views: [policyRow, trashOption])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 8
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory
        panel.isAccessoryViewDisclosed = true
        guard panel.runModal() == .OK, let source = panel.url else { return }
        let selectedPolicy = policyPicker.indexOfSelectedItem
        let policy = choices.indices.contains(selectedPolicy) ? choices[selectedPolicy].policy : .addOnly
        let applyTrash = trashOption.state == .on
        Task { await mergeLibraries(from: source, photoPolicy: policy, applyTrash: applyTrash) }
    }

    func mergeLibraries(from source: URL, photoPolicy: LibraryMergePhotoPolicy = .addOnly, applyTrash: Bool = false) async {
        guard let repository, !busy else { return }
        busy = true
        status = "Comparing library catalogues…"
        let reservedHistory = history
        let task = Task.detached(priority: .utility) {
            try await repository.mergeLibrary(from: source, photoPolicy: photoPolicy, applyTrash: applyTrash,
                                              reserving: reservedHistory, review: { preview in
                await self.reviewLibraryMerge(preview, sourceName: source.lastPathComponent)
            }) { progress in
                await self.reportLibraryMergeProgress(progress)
            }
        }
        libraryMergeTask = task
        defer { libraryMergeTask = nil; busy = false }
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }
            if result.preview.hasChanges {
                library = result.library
                let photos = mergeCount(result.preview.photosToAdd, "photo or version", "photos or versions")
                let originals = mergeCount(result.preview.originalsToCopy, "original", "originals")
                status = "Merged library · \(photos) added · \(originals) copied"
                if result.preview.photosToUpdate > 0 {
                    let updated = mergeCount(result.preview.photosToUpdate, "matching photo", "matching photos")
                    status += " · \(updated) updated"
                }
                if !result.preview.trashMoves.isEmpty {
                    batchSelection.subtract(result.preview.trashMoves.map(\.photoID))
                    selectAfterChange(preferred: selection)
                    let trashed = mergeCount(result.preview.trashMoves.count, "photo", "photos")
                    status += " · \(trashed) moved to Library Trash"
                }
            } else {
                status = "Library merge found no changes to apply"
            }
        } catch LibraryMergeError.identityConflicts {
            status = "Library merge blocked by identity conflicts"
        } catch is CancellationError {
            status = "Library merge cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "Library merge failed"
        }
    }

    private func reportLibraryMergeProgress(_ progress: ImportProgress) {
        guard libraryMergeTask?.isCancelled == false else { return }
        status = "Verified \(progress.processed) of \(progress.total) originals for library merge…"
    }

    private func reviewLibraryMerge(_ preview: LibraryMergePreview, sourceName: String) -> Bool {
        guard libraryMergeTask?.isCancelled == false else { return false }
        let alert = NSAlert()
        alert.messageText = "Review Library Merge from \(sourceName)"
        let projects = mergeCount(preview.projects.filter(\.isNew).count, "new project", "new projects")
        let albums = mergeCount(preview.albumsToAdd, "new album", "new albums")
        let photos = mergeCount(preview.photosToAdd, "new photo or version", "new photos or versions")
        let originals = mergeCount(preview.originalsToCopy, "original", "originals")
        let trashed = mergeCount(preview.trashedPhotosExcluded, "photo", "photos")
        var summary = [
            "\(projects), \(albums), \(photos).",
            "\(originals) to copy, \(preview.reusableOriginals) reusable by ID and fingerprint, \(preview.sharedOriginalsInSource) shared by source versions.",
            "Source Library Trash records excluded from this merge (\(trashed))."
        ]
        if !preview.trashMoves.isEmpty {
            let moves = mergeCount(preview.trashMoves.count, "matching photo", "matching photos")
            summary.append("\(moves) will move to Library Trash. Use Put Back to restore them.")
        }
        let differences = mergeCount(preview.photoDifferences.count, "matching photo", "matching photos")
        switch preview.photoPolicy {
        case .addOnly:
            summary.append("Matching photos keep their current values.")
        case .preferCurrent:
            summary.append("Differences on \(differences). Current edits and metadata will be kept.")
        case .preferIncoming:
            summary.append("Imported edits and metadata will replace differing values on \(differences).")
        }
        let projectRows = preview.projects.map {
            "\($0.name)\($0.isNew ? " (new project)" : "") — \($0.photosToAdd) to add, \($0.matchingPhotos) matching"
        }
        if !preview.conflicts.isEmpty {
            alert.alertStyle = .warning
            summary.append("Identity conflicts prevent the merge.")
        }
        alert.informativeText = summary.joined(separator: "\n\n")
        let photoRows = preview.photoDifferences.map {
            let scope = $0.projectName.map { " (\($0))" } ?? ""
            return "\($0.photoName)\(scope) — \($0.fields.joined(separator: ", "))"
        }
        var report = preview.conflicts + projectRows
        if !photoRows.isEmpty { report += ["", "Matching photo differences"] + photoRows }
        if !preview.trashMoves.isEmpty {
            report += ["", "Move to Library Trash"]
            report += preview.trashMoves.map {
                let scope = $0.projectName.map { " (\($0))" } ?? ""
                return $0.photoName + scope
            }
        }
        if !report.isEmpty {
            let scroll = NSTextView.scrollableTextView()
            scroll.frame.size = NSSize(width: 400, height: min(180, max(65, report.count * 24)))
            if let text = scroll.documentView as? NSTextView {
                text.string = report.joined(separator: "\n")
                text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                text.isEditable = false
                text.setAccessibilityLabel("Project breakdown, photo differences, Trash moves and identity conflicts")
            }
            alert.accessoryView = scroll
        }
        let canMerge = preview.hasChanges && preview.conflicts.isEmpty
        alert.addButton(withTitle: canMerge ? "Merge Libraries" : "Done")
        if canMerge { alert.addButton(withTitle: "Cancel") }
        let accepted = alert.runModal() == .alertFirstButtonReturn
        if accepted && canMerge { status = "Verifying originals for library merge…" }
        return accepted
    }

    private func mergeCount(_ count: Int, _ singular: String, _ plural: String) -> String {
        "\(count) \(count == 1 ? singular : plural)"
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

    func showLibraryFirstAid() {
        guard let repository, !busy else { return }
        busy = true
        status = "Checking library storage…"
        Task {
            defer { busy = false }
            do {
                let report = try await Task.detached(priority: .utility) { try repository.libraryFirstAidReport() }.value
                presentLibraryFirstAid(report)
                status = "Library First Aid review complete"
            } catch {
                self.error = error.localizedDescription
                status = "Library First Aid review failed"
            }
        }
    }

    private func presentLibraryFirstAid(_ report: LibraryFirstAidReport) {
        func originalRows(_ originals: [LibraryFirstAidOriginal]) -> [String] {
            originals.map { "\($0.name) — \($0.location)" }
        }
        let groups = [
            ("Missing managed originals", originalRows(report.missingManagedOriginals)),
            ("Offline references", originalRows(report.offlineReferences)),
            ("Untracked managed files", report.untrackedManagedFiles),
            ("Original paths requiring inspection", originalRows(report.originalsRequiringInspection)),
            ("Originals awaiting Finder Trash", report.pendingFinderTrash)
        ]
        let alert = NSAlert()
        alert.messageText = "Library First Aid"
        let totals = groups.map { "\($0.0) (\($0.1.count))" }
        alert.informativeText = (["Read-only report of catalogue and file locations."] + totals).joined(separator: "\n")
        let sections = groups.filter { !$0.1.isEmpty }.map { [$0.0] + $0.1 }
        if !sections.isEmpty {
            let scroll = NSTextView.scrollableTextView()
            scroll.frame.size = NSSize(width: 460, height: min(240, 22 * sections.reduce(0) { $0 + $1.count + 1 }))
            if let text = scroll.documentView as? NSTextView {
                text.string = sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
                text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                text.isEditable = false
                text.setAccessibilityLabel("Library First Aid findings")
            }
            alert.accessoryView = scroll
        }
        alert.addButton(withTitle: "Done")
        alert.runModal()
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
