import IsoniqueCore
import SwiftUI

extension Workspace {
    var metadataEditingTargets: [Photo] {
        guard !busy, !isViewingTrash, repository != nil else { return [] }
        if batchMode { return photos.filter { batchSelection.contains($0.id) } }
        return selected.map { [$0] } ?? []
    }

    var canAdjustCaptureDate: Bool { !metadataEditingTargets.isEmpty }

    func openCaptureDateCorrection() {
        let targets = metadataEditingTargets
        guard !targets.isEmpty else { return }
        captureDateCorrection = CaptureDateCorrection(photos: targets, preferredReferenceID: selection)
    }

    @discardableResult
    func applyCaptureDateCorrection(_ preview: CaptureDateCorrection.Preview,
                                    for correction: CaptureDateCorrection) -> Bool {
        guard !busy, !isViewingTrash, !preview.changes.isEmpty else { return false }
        let originalValues = correction.originalValues
        let targets = library.activePhotos.filter { originalValues[$0.id] != nil }
        guard targets.count == originalValues.count,
              targets.allSatisfy({ originalValues[$0.id] == $0.captureDate }) else {
            error = "The selected capture dates have changed. Reopen Adjust Date and Time to review them."
            return false
        }
        var draft = library
        guard let previous = draft.replaceCaptureDates(preview.changes) else { return false }
        var nextHistory = history
        nextHistory.record(.captureDates(previous))
        guard commit(draft, history: nextHistory) else { return false }
        if selected == nil { selectAfterChange(preferred: selection) }
        let count = previous.count
        status = count == 1 ? "Adjusted capture date for 1 photo" : "Adjusted capture dates for \(count) photos"
        if preview.skipped > 0 { status += " · \(preview.skipped) without a valid date skipped" }
        return true
    }
}

struct CaptureDateView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    private let correction: CaptureDateCorrection
    @State private var value: String
    @State private var preservingIntervals: Bool

    init(correction: CaptureDateCorrection) {
        self.correction = correction
        _value = State(initialValue: correction.referenceValue ?? "")
        _preservingIntervals = State(initialValue: correction.originalValues.count > 1 && correction.referenceValue != nil)
    }

    var body: some View {
        let count = correction.originalValues.count
        let result = Result { try correction.preview(value, preservingIntervals: preservingIntervals) }
        let preview = try? result.get()
        VStack(alignment: .leading, spacing: 16) {
            Text("Adjust Date and Time").font(.title2.bold())
            Text(count == 1 ? "1 selected photo" : "\(count) selected photos")
                .foregroundStyle(.secondary)
            if let reference = correction.referenceValue, let name = correction.referenceName {
                LabeledContent(count > 1 ? "Reference photo" : "Current capture time") {
                    Text(count > 1 ? "\(name) · \(reference)" : reference).textSelection(.enabled)
                }
            }
            if count > 1, correction.referenceValue != nil {
                Toggle("Keep intervals between photos", isOn: $preservingIntervals)
            }
            if count > 1, !preservingIntervals {
                Text("Set the same capture time on all selected photos.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Adjusted capture time", text: $value, prompt: Text("2025:03:08 14:25:00"))
                .accessibilityIdentifier("CaptureDateInput")
            Text("Use YYYY:MM:DD HH:mm:ss in the camera’s local time. The original files are preserved.")
                .font(.caption).foregroundStyle(.secondary)
            if let preview {
                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.changes.count == 1 ? "1 photo will change" : "\(preview.changes.count) photos will change")
                    if preview.skipped > 0 {
                        Text("\(preview.skipped) without a valid capture time will be skipped.")
                    }
                }
                .font(.caption)
                .accessibilityIdentifier("CaptureDatePreview")
            } else if !value.isEmpty, case .failure(let error) = result {
                Text(error.localizedDescription).font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Adjust") {
                    guard let preview else { return }
                    if model.applyCaptureDateCorrection(preview, for: correction) || model.error != nil {
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(preview?.changes.isEmpty != false)
            }
        }
        .padding(24)
        .frame(width: 550)
    }
}
