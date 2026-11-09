import SwiftUI
import IsoniqueCore

struct ImportOptionsView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @AppStorage("import.options") private var savedOptions = Data()
    @AppStorage("import.presets") private var savedPresets = Data()
    @AppStorage("history.persist") private var persistHistory = false
    @State private var options = ImportOptions()
    @State private var name = ""
    var presets: [ImportPreset] { (try? JSONDecoder().decode([ImportPreset].self, from: savedPresets)) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(model.pendingImport.isEmpty ? "Import & History Options" : "Import Options").font(.title2.bold())
            Form {
                Picker("RAW + JPEG", selection: $options.pairing) { ForEach(PairingMode.allCases) { Text($0.title).tag($0) } }
                Text("Both links matching files and opens the chosen original; switch in Info. Edits stay separate. Only filters all input files. Prefer keeps unpaired files of either format.").font(.caption).foregroundStyle(.secondary)
                TextField("Name prefix", text: $options.prefix)
                Text("Changes catalogue and export names; source files are never renamed.").font(.caption).foregroundStyle(.secondary)
                Toggle("Apply metadata preset (replaces embedded values)", isOn: $options.applyMetadata)
                Group {
                    TextField("Caption", text: $options.caption)
                    TextField("Keywords, separated by commas", text: $options.keywords)
                    Picker("Rating", selection: $options.rating) {
                        Text("Rejected").tag(-1); Text("Unrated").tag(0)
                        ForEach(1...5, id: \.self) { Text("\($0) stars").tag($0) }
                    }
                }.disabled(!options.applyMetadata)
                Toggle("Read matching .xmp sidecars", isOn: $options.readSidecars)
                Text("Sidecar caption, keywords and rating override the preset. Invalid sidecars are reported. Use File → Import XML / XMP Metadata for existing photos.").font(.caption).foregroundStyle(.secondary)
                Toggle("Keep Undo/Redo history after closing", isOn: $persistHistory).onChange(of: persistHistory) { _, _ in model.save() }
                Text("Remembers the latest 100 edits per library. Turning this off removes saved history; session Undo still works.").font(.caption).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                TextField("Preset name", text: $name)
                Button("Save Preset") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    var all = presets.filter { $0.name != trimmed }
                    all.append(ImportPreset(name: trimmed, options: options)); save(all)
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            HStack {
                Menu("Load Preset") { ForEach(presets) { preset in Button(preset.name) { options = preset.options; name = preset.name } } }.disabled(presets.isEmpty)
                Menu("Delete Preset") { ForEach(presets) { preset in Button(preset.name) { save(presets.filter { $0.id != preset.id }) } } }.disabled(presets.isEmpty)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(model.pendingImport.isEmpty ? "Save Options" : "Import") {
                    savedOptions = (try? JSONEncoder().encode(options)) ?? Data()
                    let urls = model.pendingImport; model.pendingImport = []; dismiss()
                    if !urls.isEmpty { model.importURLs(urls, options: options) }
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 580)
        .onAppear { options = (try? JSONDecoder().decode(ImportOptions.self, from: savedOptions)) ?? ImportOptions() }
    }
    func save(_ presets: [ImportPreset]) { savedPresets = (try? JSONEncoder().encode(presets)) ?? Data() }
}
