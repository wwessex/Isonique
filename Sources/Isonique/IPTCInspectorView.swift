import IsoniqueCore
import SwiftUI

struct IPTCInspectorView: View {
    let photo: Photo

    @EnvironmentObject private var model: Workspace
    @State private var expanded = false
    @State private var inherited: IPTCMetadata?
    @State private var draft: [IPTCField: String] = [:]

    var body: some View {
        DisclosureGroup("IPTC Metadata", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if inherited != nil {
                    ForEach(IPTCField.allCases) { field in
                        Text(field.title).foregroundStyle(.secondary)
                        TextField(field == .creator ? String(localized: "One creator per line") : field.title,
                                  text: binding(for: field), axis: field == .creator ? .vertical : .horizontal)
                            .lineLimit(1...3)
                            .accessibilityLabel(field.title)
                            .accessibilityIdentifier("InfoIPTC-\(field.rawValue)")
                    }
                    HStack {
                        Button("Discard Changes") { draft.removeAll() }
                            .disabled(draft.isEmpty)
                        Button("Save IPTC Metadata", action: save)
                            .disabled(edits.isEmpty || model.busy || model.isViewingTrash)
                    }
                } else {
                    ProgressView("Reading IPTC metadata…")
                }
            }
            .padding(.top, 8)
            .task(id: model.repository?.root) {
                inherited = nil
                let repository = model.repository
                let source = photo
                let metadata = await Task.detached(priority: .userInitiated) {
                    repository?.embeddedIPTC(for: source) ?? IPTCMetadata()
                }.value
                if !Task.isCancelled { inherited = metadata }
            }
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
