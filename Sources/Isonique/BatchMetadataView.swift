import IsoniqueCore
import SwiftUI

extension Workspace {
    var canOpenBatchMetadata: Bool { !metadataEditingTargets.isEmpty }

    func openBatchMetadata() {
        let targets = metadataEditingTargets
        guard !targets.isEmpty else { return }
        batchMetadataReview = BatchMetadataReview(photos: targets)
    }

    @discardableResult
    func applyBatchMetadata(_ preview: BatchMetadataReview.Preview, for review: BatchMetadataReview) -> Bool {
        guard !busy, !isViewingTrash, !preview.rows.isEmpty else { return false }
        var draft = library
        guard let previous = review.apply(preview, to: &draft) else {
            error = "The selected photos or their metadata have changed. Reopen Batch Change to review them."
            return false
        }
        var nextHistory = history
        nextHistory.record(.batchMetadata(previous))
        guard commit(draft, history: nextHistory) else { return false }
        if selected == nil { selectAfterChange(preferred: selection) }
        let count = previous.count
        status = count == 1 ? "Updated metadata for 1 photo" : "Updated metadata for \(count) photos"
        return true
    }
}

struct BatchMetadataView: View {
    let review: BatchMetadataReview

    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var changeCaption = false
    @State private var caption = ""
    @State private var keywordMode = BatchKeywordMode.unchanged
    @State private var keywords = ""

    var body: some View {
        let preview = review.preview(caption: changeCaption ? caption : nil, keywordMode: keywordMode, keywords: keywords)
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Change Metadata").font(.title2.bold())
            Toggle("Replace caption", isOn: $changeCaption)
            if changeCaption {
                TextField("New caption", text: $caption, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...3)
                    .accessibilityIdentifier("BatchCaptionInput")
                Text("Leave the new caption empty to clear it.").font(.caption).foregroundStyle(.secondary)
            }
            Picker("Keywords", selection: $keywordMode) {
                ForEach(BatchKeywordMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
            }
            .pickerStyle(.segmented)
            if keywordMode != .unchanged {
                TextField("New keywords, separated by commas", text: $keywords)
                    .accessibilityIdentifier("BatchKeywordInput")
                if keywordMode == .replace {
                    Text("Leave the new keywords empty to clear them.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Preview").font(.headline)
            Text("\(preview.rows.count) of \(review.photoCount) selected photos will change")
                .font(.subheadline).foregroundStyle(.secondary)
                .accessibilityIdentifier("BatchMetadataCount")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(preview.rows) { row in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(row.name).font(.subheadline.bold())
                            if let caption = row.after.caption {
                                fieldPreview("Caption", before: row.before.caption ?? "", after: caption)
                            }
                            if let keywords = row.after.keywords {
                                fieldPreview("Keywords", before: row.before.keywords ?? "", after: keywords)
                            }
                            Divider()
                        }
                    }
                }
            }
            .frame(height: 220)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Apply Changes") {
                    if model.applyBatchMetadata(preview, for: review) || model.error != nil { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview.rows.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
    }

    private func fieldPreview(_ name: String, before: String, after: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption.bold())
            HStack(alignment: .top, spacing: 14) {
                previewValue("Current", value: before)
                previewValue("After", value: after)
            }
        }
    }

    private func previewValue(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value.isEmpty ? "Empty" : value)
                .font(.callout)
                .foregroundStyle(value.isEmpty ? .secondary : .primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
