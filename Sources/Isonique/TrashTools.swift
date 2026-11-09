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
            showTrashReview(review)
            status = review.photos.isEmpty ? "Library Trash is empty" : "Library Trash review complete"
        } catch {
            self.error = error.localizedDescription
            status = "Library Trash review failed"
        }
    }

    private func showTrashReview(_ review: LibraryTrashReview) {
        let alert = NSAlert()
        alert.messageText = "Review Empty Library Trash"
        alert.addButton(withTitle: "Done")
        if review.photos.isEmpty {
            alert.informativeText = "Library Trash is empty."
        } else {
            let count = review.photos.count
            let records = count == 1 ? "1 photo record" : "\(count) photo records"
            let groups = Dictionary(grouping: review.originals, by: \.disposition)
            let totals = LibraryTrashOriginalDisposition.allCases.map { "\($0.title) (\(groups[$0]?.count ?? 0))" }
            alert.informativeText = (["Read-only review of \(records) in Library Trash."] + totals).joined(separator: "\n")

            var sections = [["Photo records in Library Trash"] + review.photos.map {
                let scope = $0.projectName.map { " (\($0))" } ?? ""
                return $0.name + scope
            }]
            for disposition in LibraryTrashOriginalDisposition.allCases {
                if let originals = groups[disposition] {
                    sections.append([disposition.title] + originals.map(\.filename))
                }
            }
            let scroll = NSTextView.scrollableTextView()
            scroll.frame.size = NSSize(width: 420, height: min(240, 20 * sections.reduce(0) { $0 + $1.count + 1 }))
            if let text = scroll.documentView as? NSTextView {
                text.string = sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
                text.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
                text.isEditable = false
                text.setAccessibilityLabel("Library Trash records and original dispositions")
            }
            alert.accessoryView = scroll
        }
        alert.runModal()
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
