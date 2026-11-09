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
    @State private var projectName = ""
    var presets: [ImportPreset] { (try? JSONDecoder().decode([ImportPreset].self, from: savedPresets)) ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(!model.hasPendingImport ? "Import & History Options" : "Import Options").font(.title2.bold())
            Form {
                if let device = model.pendingDeviceImport {
                    LabeledContent("Source", value: device.name)
                    Text("Originals are copied into the library. The camera or card is never changed.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Picker("Original storage", selection: Binding(get: { options.storage ?? .managed }, set: { options.storage = $0 })) {
                        ForEach(OriginalStorage.allCases) { storage in Text(storage.rawValue).tag(storage) }
                    }
                    if options.storage == .referenced {
                        Text("Isonique stores a link. Keep these files and back them up separately.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Toggle("Create a project on import", isOn: Binding(get: { options.createProject == true }, set: { options.createProject = $0 }))
                if options.createProject == true && model.hasPendingImport {
                    TextField("Project name", text: $projectName, prompt: Text(defaultProjectName))
                }
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
                Button(!model.hasPendingImport ? "Save Options" : "Import") {
                    savedOptions = (try? JSONEncoder().encode(options)) ?? Data()
                    let urls = model.pendingImport
                    let device = model.pendingDeviceImport
                    let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let project = options.createProject == true ? (name.isEmpty ? defaultProjectName : name) : nil
                    if model.hasPendingImport { model.importURLs(urls, options: options, newProjectName: project, device: device) }
                    dismiss()
                }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 580)
        .onAppear { options = (try? JSONDecoder().decode(ImportOptions.self, from: savedOptions)) ?? ImportOptions() }
    }
    private var defaultProjectName: String {
        if let device = model.pendingDeviceImport { return device.name }
        if model.pendingImport.count == 1, let first = model.pendingImport.first, first.hasDirectoryPath {
            return first.lastPathComponent
        }
        return "Import " + Date().formatted(date: .abbreviated, time: .shortened)
    }
    func save(_ presets: [ImportPreset]) { savedPresets = (try? JSONEncoder().encode(presets)) ?? Data() }
}

struct ImportProgressBar: View {
    @EnvironmentObject var model: Workspace

    var body: some View {
        HStack(spacing: 12) {
            if model.cancellingImport {
                ProgressView().controlSize(.small)
                Text("Stopping after the current file…")
            } else if let progress = model.importProgress, progress.total > 0 {
                ProgressView(value: Double(progress.processed), total: Double(progress.total))
                    .accessibilityLabel("Import progress").frame(width: 140)
                Text("\(progress.processed) of \(progress.total) processed").monospacedDigit()
                if let filename = progress.filename { Text(filename).lineLimit(1).foregroundStyle(.secondary) }
            } else {
                ProgressView().controlSize(.small)
                Text("Finding photos to import…")
            }
            Spacer()
            Button("Cancel Import", action: model.cancelImport).disabled(model.cancellingImport)
        }.font(.caption).padding(.horizontal, 18).padding(.vertical, 8).background(.ultraThinMaterial)
    }
}
