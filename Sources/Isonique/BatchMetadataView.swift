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
    @State private var iptcFields: Set<IPTCField> = []
    @State private var iptcText: [IPTCField: String] = [:]
    @State private var showIPTC = false
    @State private var presetName = ""
    @State private var presetError = false
    @State private var pendingDeletion: MetadataPreset?

    private var values: MetadataPresetValues {
        var metadata = IPTCMetadata()
        for field in iptcFields { metadata[field] = field.values(from: iptcText[field, default: ""]) }
        return MetadataPresetValues(caption: changeCaption ? caption : nil, keywordMode: keywordMode,
                                    keywords: keywords, iptc: metadata)
    }

    var body: some View {
        let preview = review.preview(values)
        VStack(alignment: .leading, spacing: 12) {
            Text("Batch Change Metadata").font(.title2.bold())
            DisclosureGroup("Reusable Metadata Presets") {
                HStack {
                    Menu("Load Metadata Preset") {
                        ForEach(model.metadataPresets) { preset in Button(preset.name) { load(preset.values) } }
                    }.disabled(model.metadataPresets.isEmpty)
                    Menu("Delete Metadata Preset") {
                        ForEach(model.metadataPresets) { preset in Button(preset.name) { pendingDeletion = preset } }
                    }.disabled(model.metadataPresets.isEmpty)
                }.padding(.top, 4)
                HStack {
                    TextField("Metadata preset name", text: $presetName)
                    Button("Save Metadata Preset") {
                        if model.saveMetadataPreset(named: presetName, values: values) { presetName = "" }
                        else { presetError = true }
                    }
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !values.hasChanges)
                }
            }
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
            DisclosureGroup("IPTC Metadata", isExpanded: $showIPTC) {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    ForEach(IPTCField.allCases) { field in
                        GridRow(alignment: .top) {
                            Toggle(field.title, isOn: Binding(get: { iptcFields.contains(field) }, set: { enabled in
                                if enabled { iptcFields.insert(field) } else { iptcFields.remove(field) }
                            }))
                            TextField(field == .creator ? String(localized: "One creator per line") : field.title,
                                      text: Binding(get: { iptcText[field, default: ""] }, set: { iptcText[field] = $0 }),
                                      axis: field == .creator ? .vertical : .horizontal)
                                .lineLimit(1...3)
                                .accessibilityLabel(field.title)
                                .accessibilityIdentifier("BatchIPTC-\(field.rawValue)")
                                .disabled(!iptcFields.contains(field))
                        }
                    }
                }
                .padding(.top, 4)
                Text("Checked fields are replaced. Leave one empty to clear it.").font(.caption).foregroundStyle(.secondary)
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
                            ForEach(row.after.iptc ?? []) { edit in
                                let previous = row.before.iptc?.first { $0.field == edit.field }
                                fieldPreview(edit.field.title, before: previous?.text ?? String(localized: "From original"),
                                             after: edit.text ?? "")
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
        .alert("Metadata Preset Already Exists", isPresented: $presetError) {
            Button("OK", role: .cancel) {}
        } message: { Text("Choose a different name for the preset.") }
        .confirmationDialog("Delete Metadata Preset?", isPresented: Binding(
            get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }
        ), presenting: pendingDeletion) { preset in
            Button("Delete", role: .destructive) { model.deleteMetadataPreset(preset.id) }
        } message: { preset in Text(preset.name) }
    }

    private func load(_ values: MetadataPresetValues) {
        changeCaption = values.caption != nil
        caption = values.caption ?? ""
        keywordMode = values.keywordMode
        keywords = values.keywords
        iptcText = [:]
        for field in IPTCField.allCases {
            iptcText[field] = values.iptc[field]?.joined(separator: "\n")
        }
        iptcFields = Set(iptcText.keys)
        showIPTC = !iptcFields.isEmpty
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
