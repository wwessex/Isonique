import SwiftUI
import IsoniqueCore

struct ExportOptionsView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @AppStorage("export.presets") private var savedPresets = Data()
    @AppStorage("export.lastOptions") private var lastOptions = Data()
    @State private var options = ExportOptions()
    @State private var name = ""
    var presets: [ExportPreset] { (try? JSONDecoder().decode([ExportPreset].self, from: savedPresets)) ?? [] }

    var body: some View {
        let batchPreview = model.batchMode ? Result {
            try BatchExport.plan(photos: model.batchPhotos, projects: model.library.projects, options: options)
        } : nil
        let batchPlan = try? batchPreview?.get()
        let invalid = invalidDimensions || (model.batchMode && batchPlan?.entries.isEmpty != false)
        VStack(alignment: .leading, spacing: 18) {
            Text(model.batchMode ? "Export Selected Photos" : "Export Photo").font(.title2.bold())
            Text(model.batchMode ? "\(model.batchPhotos.count) selected photos" : (model.selected?.displayName ?? "")).foregroundStyle(.secondary)
            HStack {
                Menu("Load preset") {
                    ForEach(presets) { preset in Button(preset.name) { options = preset.options } }
                }.disabled(presets.isEmpty)
                Menu("Delete preset") {
                    ForEach(presets) { preset in Button(preset.name) { save(presets.filter { $0.id != preset.id }) } }
                }.disabled(presets.isEmpty)
            }
            Picker("Format", selection: $options.format) { ForEach(ExportFormat.allCases) { Text($0.rawValue).tag($0) } }
            if options.format == .original {
                Text("Copies the original file byte for byte, including its embedded metadata and GPS.").foregroundStyle(.secondary)
            } else {
                if options.format == .jpeg || options.format == .heif {
                    HStack { Text("\(options.format.rawValue) quality"); Slider(value: $options.quality, in: 0.1...1); Text("\(Int(options.quality * 100))%").monospacedDigit().frame(width: 45) }
                }
                if options.format == .tiff {
                    Picker("TIFF compression", selection: Binding(
                        get: { options.tiffCompression ?? .uncompressed },
                        set: { options.tiffCompression = $0 }
                    )) {
                        ForEach(TIFFCompression.allCases) { compression in
                            Text(compression.rawValue).tag(compression)
                        }
                    }
                }
                HStack { Text("Longest edge (pixels)"); TextField("0", value: $options.maxDimension, format: .number).frame(width: 100) }
                Text("0 keeps full resolution. Images are reduced proportionally and never enlarged.").font(.caption).foregroundStyle(.secondary)
                GroupBox("Include metadata") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("EXIF — camera and capture information", isOn: $options.exif)
                        Toggle("IPTC — current metadata and keywords", isOn: $options.iptc)
                        Toggle("GPS — current photo location", isOn: $options.gps)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Text("Unchecked metadata is omitted. Original files always retain their embedded metadata.").font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Write matching XMP sidecar", isOn: Binding(
                get: { options.xmpSidecar == true },
                set: { options.xmpSidecar = $0 ? true : nil }
            ))
            Text("The separate .xmp file carries your current IPTC fields, caption, rating and keyword paths.")
                .font(.caption).foregroundStyle(.secondary)
            if let batchPreview {
                batchNaming(batchPreview)
            }
            HStack {
                TextField("Preset name", text: $name)
                Button("Save preset") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    var all = presets.filter { $0.name != trimmed }
                    all.append(ExportPreset(name: trimmed, options: options)); save(all); name = ""
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || invalid)
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Choose Destination…") {
                    lastOptions = (try? JSONEncoder().encode(options)) ?? Data()
                    let selected = options
                    dismiss()
                    DispatchQueue.main.async { model.exportWithOptions(selected, batchPlan: batchPlan) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(invalid)
            }
        }.padding(26).frame(width: model.batchMode ? 560 : 510)
            .onAppear { options = (try? JSONDecoder().decode(ExportOptions.self, from: lastOptions)) ?? ExportOptions() }
    }

    private func batchNaming(_ preview: Result<BatchExport.Plan, Error>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Filename template", text: Binding(
                    get: { options.filenameTemplate ?? "" },
                    set: { options.filenameTemplate = $0.isEmpty ? nil : $0 }
                ), prompt: Text("Sequence and version name"))
                    .monospaced()
                    .help("Leave blank for numbered version names. Isonique adds the file extension.")
                Menu("Templates") {
                    Button("Sequence and Version Name") { options.filenameTemplate = nil }
                    Button("Version Name") { options.filenameTemplate = "{version}" }
                    Button("Original Filename") { options.filenameTemplate = "{original}" }
                    Button("Project and Sequence") { options.filenameTemplate = "{project}-{sequence}" }
                }.fixedSize()
            }
            Text("{original}, {catalogue}, {version}, {project}, {year}, {month}, {day}, {sequence}")
                .font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
            switch preview {
            case .success(let plan):
                Text("Filename Preview").font(.headline)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(plan.entries) { entry in
                            Text(entry.filename).textSelection(.enabled)
                            if let sidecar = entry.sidecarFilename {
                                Text(sidecar).foregroundStyle(.secondary).textSelection(.enabled)
                            }
                        }
                    }.font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
                }.frame(height: min(105, CGFloat(plan.entries.count) * (options.xmpSidecar == true ? 42 : 22)))
                    .accessibilityLabel("Filename Preview")
            case .failure(let error):
                Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private var invalidDimensions: Bool { options.format != .original && !(0...100000).contains(options.maxDimension) }
    func save(_ all: [ExportPreset]) { savedPresets = (try? JSONEncoder().encode(all)) ?? Data() }
}
