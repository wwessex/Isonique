import IsoniqueCore
import SwiftUI

struct IPTCFieldEditor {
    let isReady: Bool
    let binding: (IPTCField) -> Binding<String>
    let canSave: Bool
    let hasDraft: Bool
    let save: () -> Void
    let discard: () -> Void

    @ViewBuilder var actions: some View {
        if isReady {
            HStack {
                Button("Discard Changes", action: discard).disabled(!hasDraft)
                Button("Save IPTC Metadata", action: save).disabled(!canSave)
            }
        }
    }

    @ViewBuilder func row(_ field: IPTCField) -> some View {
        if isReady {
            Text(field.title).foregroundStyle(.secondary)
            TextField(field == .creator ? String(localized: "One creator per line") : field.title,
                      text: binding(field), axis: field == .creator ? .vertical : .horizontal)
                .lineLimit(1...3)
                .accessibilityLabel(field.title)
                .accessibilityIdentifier("InfoIPTC-\(field.rawValue)")
        } else {
            LabeledContent(field.title, value: String(localized: "Reading…"))
        }
    }
}

struct IPTCMetadataEditor<Content: View>: View {
    private struct Request: Equatable {
        let root: URL?
        let filename: String
        let referencedPath: String?
        let originalRevision: Int
        let isActive: Bool
    }

    let photo: Photo
    var isActive = true
    @ViewBuilder var content: (IPTCFieldEditor) -> Content

    @EnvironmentObject private var model: Workspace
    @State private var inherited: IPTCMetadata?
    @State private var draft: [IPTCField: String] = [:]

    var body: some View {
        let request = Request(root: model.repository?.root, filename: photo.filename, referencedPath: photo.referencedPath,
                              originalRevision: model.originalStatusRevision, isActive: isActive)
        content(IPTCFieldEditor(isReady: inherited != nil, binding: binding,
                               canSave: !edits.isEmpty && !model.busy && !model.isViewingTrash,
                               hasDraft: !draft.isEmpty, save: save, discard: { draft.removeAll() }))
            .task(id: request) {
                guard request.isActive else { return }
                inherited = nil
                let repository = model.repository
                let source = photo
                let metadata = await Task.detached(priority: .userInitiated) {
                    repository?.embeddedIPTC(for: source) ?? IPTCMetadata()
                }.value
                if !Task.isCancelled { inherited = metadata }
            }
        .onChange(of: photo.iptc) { draft.removeAll() }
    }

    private func values(for field: IPTCField) -> [String] {
        photo.iptc?[field] ?? inherited?[field] ?? []
    }

    private func binding(for field: IPTCField) -> Binding<String> {
        Binding(get: { draft[field] ?? values(for: field).joined(separator: "\n") },
                set: { draft[field] = $0 })
    }

    private var edits: [IPTCFieldEdit] {
        IPTCField.allCases.compactMap { field in
            guard let text = draft[field] else { return nil }
            let replacement = field.values(from: text)
            guard replacement != values(for: field) else { return nil }
            return IPTCFieldEdit(field: field, values: replacement)
        }
    }

    private func save() {
        guard model.selected?.id == photo.id else { return }
        let changes = edits
        guard !changes.isEmpty else { return }
        model.edit { $0.applyIPTC(changes) }
    }
}

struct IPTCInspectorView: View {
    let photo: Photo
    @State private var expanded = false

    var body: some View {
        IPTCMetadataEditor(photo: photo, isActive: expanded) { editor in
            DisclosureGroup("IPTC Metadata", isExpanded: $expanded) {
                if expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        if editor.isReady {
                            ForEach(IPTCField.allCases) { editor.row($0) }
                            editor.actions
                        } else {
                            ProgressView("Reading IPTC metadata…")
                        }
                    }.padding(.top, 8)
                }
            }
        }
    }
}
