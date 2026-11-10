import IsoniqueCore
import SwiftUI

extension Workspace {
    var canReviewInheritedIPTC: Bool { metadataEditingTargets.contains(where: \.hasUncataloguedIPTC) }

    func openInheritedIPTCReview() {
        let targets = metadataEditingTargets
        guard let repository, targets.contains(where: \.hasUncataloguedIPTC) else { return }
        busy = true
        status = "Verifying originals and reading IPTC metadata…"
        let scan = Task.detached(priority: .userInitiated) {
            try repository.reviewInheritedIPTC(for: targets)
        }
        inheritedIPTCScan = scan
        Task {
            defer { inheritedIPTCScan = nil; busy = false }
            do {
                let review = try await scan.value
                guard !scan.isCancelled else { throw CancellationError() }
                status = "IPTC review ready"
                inheritedIPTCReview = review
            } catch is CancellationError {
                status = "IPTC review cancelled"
            } catch {
                self.error = error.localizedDescription
                status = "IPTC review failed"
            }
        }
    }
}

struct InheritedIPTCReviewView: View {
    let review: InheritedIPTCReview
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Catalogue IPTC from Originals").font(.title2.bold())
            Text("Add the original’s title, creator, copyright or credit where the catalogue has no saved value.")
                .foregroundStyle(.secondary)
            Text("\(review.preview.rows.count) of \(review.batch.photoCount) selected photos can be updated")
                .font(.headline)
            if review.preview.rows.isEmpty && review.issues.isEmpty {
                Text("No new IPTC fields were found in the selected originals.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if !review.issues.isEmpty {
                            Text("Skipped photos").font(.headline)
                            ForEach(review.issues) { issue in
                                Text(issue.name).font(.subheadline.bold())
                                Text(issue.reason).foregroundStyle(.secondary)
                            }
                            Divider()
                        }
                        ForEach(review.preview.rows) { row in
                            Text(row.name).font(.subheadline.bold())
                            ForEach(row.after.iptc ?? []) { edit in
                                LabeledContent(edit.field.title, value: edit.text ?? "")
                            }
                            Divider()
                        }
                    }.padding(.trailing, 10)
                }.frame(height: 280)
            }
            HStack {
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Add to Catalogue") {
                    let applied = model.applyBatchMetadata(review.preview, for: review.batch)
                    if applied || model.error != nil { dismiss() }
                }.keyboardShortcut(.defaultAction)
                    .disabled(review.preview.rows.isEmpty)
            }
        }.padding(24).frame(width: 620)
    }
}
