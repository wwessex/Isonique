import AppKit
import IsoniqueCore

extension Workspace {
    var canReviewEmptyLibraryTrash: Bool { repository != nil && !busy }

    func showEmptyLibraryTrashReview() {
        Task { await reviewEmptyLibraryTrash() }
    }

    private func reviewEmptyLibraryTrash() async {
        guard let repository, !busy else { return }
        busy = true
        status = "Reviewing Library Trash…"
        defer { busy = false }
        do {
            let review = try await Task.detached(priority: .utility) { try repository.reviewEmptyLibraryTrash() }.value
            guard showTrashReview(review) else {
                status = review.photos.isEmpty && review.pendingFilenames.isEmpty ? "Library Trash is empty" : "Library Trash review complete"
                return
            }
            status = "Emptying Library Trash…"
            let result = try await Task.detached(priority: .utility) { try repository.emptyLibraryTrash(after: review) }.value
            library = result.library
            history.discardEmptiedTrash(photoIDs: result.removedPhotoIDs, originalIDs: result.removedOriginalIDs)
            batchSelection.subtract(result.removedPhotoIDs)
            selectAfterChange(preferred: selection)
            status = "Library Trash · \(result.removedPhotoIDs.count) photo records removed · \(result.movedToFinderTrash) originals moved to Finder Trash"
            if !result.pendingFilenames.isEmpty { status += " · \(result.pendingFilenames.count) awaiting Finder Trash" }
            if result.keptInLibrary > 0 { status += " · \(result.keptInLibrary) kept in Library Trash" }
            if !result.keptOriginals.isEmpty || !result.handoffErrors.isEmpty {
                showTrashResult(result)
            }
        } catch {
            self.error = error.localizedDescription
            status = "Library Trash operation failed"
        }
    }

    private func showTrashReview(_ review: LibraryTrashReview) -> Bool {
        let alert = NSAlert()
        let retry = review.photos.isEmpty || review.originals.allSatisfy { $0.disposition == .unavailable }
        alert.messageText = retry && !review.pendingFilenames.isEmpty ? "Retry Finder Trash" : "Review Empty Library Trash"
        alert.addButton(withTitle: review.canEmpty ? "Cancel" : "Done")
        if review.canEmpty {
            alert.alertStyle = .warning
            let action = alert.addButton(withTitle: retry ? "Retry Finder Trash" : "Empty Library Trash")
            action.keyEquivalent = ""
        }
        if review.photos.isEmpty && review.pendingFilenames.isEmpty {
            alert.informativeText = "Library Trash is empty."
        } else {
            let count = review.photos.count
            let records = count == 1 ? "1 photo record" : "\(count) photo records"
            let groups = Dictionary(grouping: review.originals, by: \.disposition)
            let totals = LibraryTrashOriginalDisposition.allCases.map { "\($0.title) (\(groups[$0]?.count ?? 0))" }
            var summary = ["\(records) in Library Trash."] + totals
            if !review.pendingFilenames.isEmpty {
                summary.append("Originals awaiting Finder Trash (\(review.pendingFilenames.count))")
            }
            if review.canEmpty && !retry {
                summary.append("Emptying Trash permanently removes eligible photo records and their edits. Managed candidates go to Finder Trash after verification.")
            }
            alert.informativeText = summary.joined(separator: "\n")

            var sections = [["Photo records in Library Trash"] + review.photos.map {
                let scope = $0.projectName.map { " (\($0))" } ?? ""
                return $0.name + scope
            }]
            for disposition in LibraryTrashOriginalDisposition.allCases {
                if let originals = groups[disposition] {
                    sections.append([disposition.title] + originals.map(\.filename))
                }
            }
            if !review.pendingFilenames.isEmpty {
                sections.append(["Originals awaiting Finder Trash"] + review.pendingFilenames)
            }
            alert.accessoryView = trashReport(sections, label: "Library Trash records and original dispositions")
        }
        let response = alert.runModal()
        return review.canEmpty && response == .alertSecondButtonReturn
    }

    private func showTrashResult(_ result: EmptyLibraryTrashResult) {
        let alert = NSAlert()
        alert.messageText = "Library Trash Results"
        var sections: [[String]] = []
        if !result.keptOriginals.isEmpty {
            sections.append(["Kept in Library Trash for a file check"] + result.keptOriginals)
        }
        if !result.handoffErrors.isEmpty {
            sections.append(["Finder Trash handoff"] + result.handoffErrors)
        }
        alert.informativeText = "Photo records removed (\(result.removedPhotoIDs.count)). Originals moved (\(result.movedToFinderTrash)). Awaiting Finder Trash (\(result.pendingFilenames.count)). Use Empty Library Trash to review pending originals."
        alert.accessoryView = trashReport(sections, label: "Library Trash results")
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }

    private func trashReport(_ sections: [[String]], label: String) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.frame.size = NSSize(width: 420, height: min(240, 20 * sections.reduce(0) { $0 + $1.count + 1 }))
        if let text = scroll.documentView as? NSTextView {
            text.string = sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
            text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
            text.isEditable = false
            text.setAccessibilityLabel(label)
        }
        return scroll
    }
}

private extension LibraryTrashOriginalDisposition {
    var title: String {
        switch self {
        case .finderTrashCandidate: return "Managed candidates for Finder Trash"
        case .retainedByActiveVersion: return "Managed originals kept for active photos"
        case .referenced: return "Referenced originals kept in place"
        case .unavailable: return "Managed originals requiring a file check"
        }
    }
}
