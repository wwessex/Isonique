import AppKit
import IsoniqueCore
import SwiftUI
import UniformTypeIdentifiers

enum KeywordVocabularyPreferences {
    private static let key = "metadata.keywordVocabulary"

    static func load(from preferences: UserDefaults) -> KeywordVocabulary {
        guard let data = preferences.data(forKey: key),
              let vocabulary = try? JSONDecoder().decode(KeywordVocabulary.self, from: data) else { return KeywordVocabulary() }
        return vocabulary
    }

    static func save(_ vocabulary: KeywordVocabulary, to preferences: UserDefaults) throws {
        preferences.set(try JSONEncoder().encode(vocabulary), forKey: key)
    }
}

extension Workspace {
    func updateKeywordVocabulary(_ update: (inout KeywordVocabulary) throws -> Void) throws {
        var vocabulary = KeywordVocabularyPreferences.load(from: preferences)
        try update(&vocabulary)
        try KeywordVocabularyPreferences.save(vocabulary, to: preferences)
        keywordVocabulary = vocabulary
    }

    func importKeywordVocabulary(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { throw KeywordVocabularyError.invalidEncoding }
        let incoming = try KeywordVocabulary(text: text)
        var added = 0
        try updateKeywordVocabulary { added = $0.merge(incoming) }
        return added
    }

    func exportKeywordVocabulary(to url: URL) throws {
        try keywordVocabulary.text.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct KeywordVocabularyView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var editor: Edit?
    @State private var name = ""
    @State private var message: String?
    @State private var error: String?
    @State private var confirmingDelete = false

    private enum Edit {
        case add(parent: UUID?)
        case rename(UUID)
    }

    private var selected: KeywordVocabulary.Entry? { selectedID.flatMap(model.keywordVocabulary.entry) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keyword Vocabulary").font(.title2.bold())
            Text("Build a keyword tree to use across your Isonique libraries. Import or export a UTF-8 text list with tabs for child keywords.")
                .foregroundStyle(.secondary)
            List(selection: $selectedID) {
                OutlineGroup(model.keywordVocabulary.roots, children: \.outlineChildren) { entry in
                    Text(entry.name).tag(entry.id)
                }
            }
            .overlay {
                if model.keywordVocabulary.roots.isEmpty { Text("No keywords in the vocabulary").foregroundStyle(.secondary) }
            }
            .accessibilityLabel("Vocabulary tree")
            .frame(minHeight: 220)
            .disabled(editor != nil)

            if let editor {
                HStack {
                    TextField("Keyword name", text: $name)
                        .accessibilityIdentifier("VocabularyName")
                        .onSubmit { save(editor) }
                    Button("Cancel") { self.editor = nil; error = nil }
                    Button("Save Keyword") { save(editor) }.keyboardShortcut(.defaultAction)
                }
            } else {
                HStack {
                    Button("New Keyword…") { begin(.add(parent: nil)) }
                    Button("New Child…") { begin(.add(parent: selectedID)) }.disabled(selected == nil)
                    Button("Rename…") {
                        if let selected { begin(.rename(selected.id), name: selected.name) }
                    }.disabled(selected == nil)
                    Button("Delete…") { confirmingDelete = true }.disabled(selected == nil)
                    Spacer()
                    Button("Apply Keyword") {
                        if let selected, model.addKeywords(selected.name) {
                            message = model.status
                            error = nil
                        }
                    }.disabled(selected == nil || !model.canOpenBatchMetadata)
                }
            }
            if let error { Text(error).foregroundStyle(.orange) }
            else if let message { Text(message).foregroundStyle(.secondary) }
            HStack {
                Button("Import…", action: importList).disabled(editor != nil)
                Button("Export…", action: exportList)
                    .disabled(editor != nil || model.keywordVocabulary.roots.isEmpty)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(width: 620, height: 435)
        .alert("Delete Keyword Branch?", isPresented: $confirmingDelete, presenting: selected) { entry in
            Button("Delete Branch", role: .destructive) {
                perform {
                    try model.updateKeywordVocabulary { try $0.delete(entry.id) }
                    selectedID = nil
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { entry in
            Text("Remove “\(entry.name)” and its children from the vocabulary. Photos keep their assigned keywords.")
        }
    }

    private func begin(_ edit: Edit, name: String = "") {
        editor = edit
        self.name = name
        error = nil
        message = nil
    }

    private func save(_ edit: Edit) {
        perform {
            var updatedID: UUID?
            try model.updateKeywordVocabulary { vocabulary in
                switch edit {
                case .add(let parent): updatedID = try vocabulary.add(name, under: parent)
                case .rename(let id): try vocabulary.rename(id, to: name); updatedID = id
                }
            }
            selectedID = updatedID
            editor = nil
        }
    }

    private func importList() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "Import Keyword Vocabulary")
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            let added = try model.importKeywordVocabulary(from: url)
            message = added == 1 ? String(localized: "Added 1 keyword") : String(localized: "Added \(added) keywords")
        }
    }

    private func exportList() {
        let panel = NSSavePanel()
        panel.title = String(localized: "Export Keyword Vocabulary")
        panel.nameFieldStringValue = String(localized: "Isonique Keywords") + ".txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        perform {
            try model.exportKeywordVocabulary(to: url)
            message = String(localized: "Keyword vocabulary exported")
        }
    }

    private func perform(_ action: () throws -> Void) {
        message = nil
        do { try action(); error = nil }
        catch { self.error = error.localizedDescription }
    }
}

private extension KeywordVocabulary.Entry {
    var outlineChildren: [Self]? { children.isEmpty ? nil : children }
}
