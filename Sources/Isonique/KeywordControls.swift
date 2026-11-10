import AppKit
import SwiftUI

extension View {
    func keywordShortcuts(for model: Workspace) -> some View {
        onKeyPress(phases: .down) { press in
            guard press.modifiers.contains(.option) else { return .ignored }
            // Shift may turn the digit into punctuation before SwiftUI matches the key.
            let event = NSApp.currentEvent
            let character = event?.type == .keyDown ? event?.characters(byApplyingModifiers: [])?.first : nil
            return model.keywordShortcut(KeyEquivalent(character ?? press.key.character), modifiers: press.modifiers)
        }
    }
}

extension Workspace {
    func keywordShortcut(_ key: KeyEquivalent, modifiers: EventModifiers) -> KeyPress.Result {
        let shortcutModifiers = modifiers.intersection([.option, .shift, .command, .control])
        guard shortcutModifiers == .option || shortcutModifiers == [.option, .shift],
              !modifiers.contains(.numericPad),
              showKeywordControls, let group = keywordGroups.active,
              let slot = key.character.wholeNumberValue, (1...8).contains(slot),
              group.keywords.indices.contains(slot - 1), canOpenBatchMetadata else { return .ignored }
        let keyword = group.keywords[slot - 1]
        if shortcutModifiers.contains(.shift) { removeKeywords(keyword) }
        else { addKeywords(keyword) }
        return .handled
    }
}

struct KeywordControls: View {
    @EnvironmentObject private var model: Workspace

    var body: some View {
        HStack(spacing: 10) {
            if let group = model.keywordGroups.active {
                Picker("Keyword Group", selection: Binding(
                    get: { model.keywordGroups.active?.id ?? group.id }, set: model.selectKeywordGroup)) {
                    ForEach(model.keywordGroups.groups) { Text($0.name).tag($0.id) }
                }
                .frame(maxWidth: 220)
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(group.keywords.enumerated()), id: \.element) { index, keyword in
                            Button(keyword) {
                                if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                                    model.removeKeywords(keyword)
                                } else {
                                    model.addKeywords(keyword)
                                }
                            }
                            .accessibilityLabel("Add keyword \(keyword)")
                            .accessibilityAction(named: Text("Remove keyword \(keyword)")) { model.removeKeywords(keyword) }
                            .help(index < 8
                                  ? "Add \(keyword) with Option-\(index + 1) or remove it with Option-Shift-\(index + 1) when the Browser or Viewer has focus. Shift-click also removes it."
                                  : "Click to add \(keyword) or Shift-click to remove it.")
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .disabled(!model.canOpenBatchMetadata)
                Button("Apply Group") { model.addKeywords(group.keywordText) }
                    .disabled(!model.canOpenBatchMetadata)
                    .help("Append all keywords in \(group.name) to the selected photos")
            } else {
                Text("Create a keyword group for quick assignment.").foregroundStyle(.secondary)
                Spacer()
            }
            Button {
                model.showKeywordGroupEditor = true
            } label: {
                Label("Manage Keyword Groups", systemImage: "ellipsis.circle")
            }
            .labelStyle(.iconOnly)
            .help("Manage Keyword Groups")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

struct KeywordGroupEditor: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var editing = false
    @State private var editingID: UUID?
    @State private var name = ""
    @State private var keywords = ""
    @State private var error: String?
    @State private var confirmingDelete = false

    private var selected: KeywordGroup? { model.keywordGroups.groups.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyword Groups").font(.title2.bold())
            Text("Save related keywords for quick assignment across your libraries.")
                .foregroundStyle(.secondary)
            HStack {
                if !model.keywordGroups.groups.isEmpty {
                    Picker("Group", selection: $selectedID) {
                        ForEach(model.keywordGroups.groups) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Button("Edit…") { beginEditing(selected) }.disabled(selected == nil)
                    Button("Delete…") { confirmingDelete = true }.disabled(selected == nil)
                }
                Button("New Group…") { beginEditing(nil) }
            }
            .disabled(editing)
            if editing {
                TextField("Group name", text: $name).accessibilityIdentifier("KeywordGroupName")
                TextField("Keywords, separated by commas", text: $keywords)
                    .accessibilityIdentifier("KeywordGroupValues")
            } else if let selected {
                LabeledContent("Keywords") {
                    Text(selected.keywordText).textSelection(.enabled)
                }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            HStack {
                Spacer()
                if editing {
                    Button("Cancel") { editing = false; error = nil }.keyboardShortcut(.cancelAction)
                    Button("Save Group", action: save).keyboardShortcut(.defaultAction)
                } else {
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(24)
        .frame(width: 510)
        .onAppear { selectedID = model.keywordGroups.activeID }
        .alert("Delete Keyword Group?", isPresented: $confirmingDelete, presenting: selected) { group in
            Button("Delete Group", role: .destructive) { delete(group) }
            Button("Cancel", role: .cancel) {}
        } message: { group in
            Text("“\(group.name)” will be removed from the keyword controls. Photos keep their assigned keywords.")
        }
    }

    private func beginEditing(_ group: KeywordGroup?) {
        editingID = group?.id
        name = group?.name ?? ""
        keywords = group?.keywordText ?? ""
        error = nil
        editing = true
    }

    private func save() {
        do {
            let group = try KeywordGroup(id: editingID ?? UUID(), name: name, keywordText: keywords)
            try model.saveKeywordGroup(group)
            selectedID = group.id
            editing = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ group: KeywordGroup) {
        do {
            try model.deleteKeywordGroup(group.id)
            selectedID = model.keywordGroups.activeID
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
