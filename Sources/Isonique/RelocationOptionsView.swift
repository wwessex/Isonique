import SwiftUI
import IsoniqueCore

struct RelocationPresetStore {
    static let key = "relocation.presets"
    let preferences: UserDefaults

    func load() -> [OriginalRelocationPreset] {
        guard let data = preferences.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([OriginalRelocationPreset].self, from: data) else { return [] }
        var ids: Set<UUID> = []
        return decoded.filter { (try? $0.validate()) != nil && ids.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func save(_ preset: OriginalRelocationPreset) throws {
        try preset.validate()
        var all = load().filter { $0.id != preset.id }
        guard !all.contains(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) else {
            throw OriginalRelocationTemplateError.invalid("A relocation preset with this name already exists.")
        }
        all.append(preset)
        try write(all)
    }

    func delete(_ id: UUID) throws {
        try write(load().filter { $0.id != id })
    }

    private func write(_ presets: [OriginalRelocationPreset]) throws {
        preferences.set(try JSONEncoder().encode(presets), forKey: Self.key)
    }
}

struct RelocationOptionsView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var presets: [OriginalRelocationPreset] = []
    @State private var presetID: UUID?
    @State private var filename = OriginalRelocationFilename.original
    @State private var subfolders = OriginalRelocationSubfolders.none
    @State private var keepReferencedSources = true
    @State private var editing = false
    @State private var editID: UUID?
    @State private var presetName = ""
    @State private var filenamePattern = "{original}-{sequence}"
    @State private var subfolderPattern = ""
    @State private var error: String?

    private var store: RelocationPresetStore { RelocationPresetStore(preferences: model.preferences) }
    private var selected: OriginalRelocationPreset? { presets.first { $0.id == presetID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Relocate Originals").font(.title2.bold())
            Text("Choose how to name and organise the copies. You’ll review the exact paths before Isonique moves anything.")
                .foregroundStyle(.secondary)
            HStack {
                Picker("Preset", selection: $presetID) {
                    Text("Built-in choices").tag(nil as UUID?)
                    ForEach(presets) { Text($0.name).tag(Optional($0.id)) }
                }
                Button("New Preset…") { beginEditing(nil) }
                if let selected {
                    Button("Edit…") { beginEditing(selected) }
                    Button("Delete") { delete(selected) }
                }
            }.disabled(editing)

            if editing {
                editor
            } else if let selected {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Filename template")
                        Text(selected.filenamePattern).monospaced().textSelection(.enabled)
                    }
                    GridRow {
                        Text("Subfolder template")
                        Text(selected.subfolderPattern.isEmpty ? "No subfolders" : selected.subfolderPattern)
                            .monospaced().textSelection(.enabled)
                    }
                }
            } else {
                Picker("Filenames", selection: $filename) {
                    ForEach(OriginalRelocationFilename.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("Subfolders", selection: $subfolders) {
                    ForEach(OriginalRelocationSubfolders.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
            if model.relocationHasReferencedOriginals {
                Toggle("Keep copies at previous referenced locations", isOn: $keepReferencedSources)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Destination…") {
                    model.pendingRelocationOptions = OriginalRelocationOptions(
                        filename: filename, subfolders: subfolders, keepReferencedSources: keepReferencedSources,
                        customPreset: selected)
                    dismiss()
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(editing)
            }
        }.padding(24).frame(width: 560)
            .onAppear { presets = store.load() }
    }

    private var editor: some View {
        GroupBox("Custom Preset") {
            VStack(alignment: .leading, spacing: 8) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Preset name")
                        TextField("Preset name", text: $presetName, prompt: Text("Client delivery")).labelsHidden()
                    }
                    GridRow {
                        Text("Filename template")
                        TextField("Filename template", text: $filenamePattern).labelsHidden().monospaced()
                    }
                    GridRow {
                        Text("Subfolder template")
                        TextField("Subfolder template", text: $subfolderPattern, prompt: Text("Leave blank for no subfolders"))
                            .labelsHidden().monospaced()
                    }
                }
                Text("Tokens: {original}, {catalogue}, {project}, {year}, {month}, {day}, {sequence}")
                    .font(.caption.monospaced()).textSelection(.enabled)
                Text("Isonique adds the file extension. Use / between subfolders, for example {project}/{year}/{month}.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Cancel Editing") { editing = false; error = nil }
                    Button("Save Preset", action: save).disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(4)
        }
    }

    private func beginEditing(_ preset: OriginalRelocationPreset?) {
        editID = preset?.id
        presetName = preset?.name ?? ""
        filenamePattern = preset?.filenamePattern ?? "{original}-{sequence}"
        subfolderPattern = preset?.subfolderPattern ?? ""
        error = nil
        editing = true
    }

    private func save() {
        do {
            let preset = try OriginalRelocationPreset(id: editID ?? UUID(), name: presetName,
                filenamePattern: filenamePattern, subfolderPattern: subfolderPattern)
            try store.save(preset)
            presets = store.load()
            presetID = preset.id
            editing = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func delete(_ preset: OriginalRelocationPreset) {
        do {
            try store.delete(preset.id)
            presets = store.load()
            presetID = nil
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
