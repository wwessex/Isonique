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
                Text("Copies the original file byte for byte, including all original metadata and GPS. Adjustments and edited captions are not applied.").foregroundStyle(.secondary)
            } else {
                if options.format == .jpeg {
                    HStack { Text("JPEG quality"); Slider(value: $options.quality, in: 0.1...1); Text("\(Int(options.quality * 100))%").monospacedDigit().frame(width: 45) }
                }
                HStack { Text("Longest edge (pixels)"); TextField("0", value: $options.maxDimension, format: .number).frame(width: 100) }
                Text("0 keeps full resolution. Images are reduced proportionally and never enlarged.").font(.caption).foregroundStyle(.secondary)
                GroupBox("Include metadata") {
                    VStack(alignment: .leading, spacing: 10) {
                        Toggle("EXIF — camera and capture information", isOn: $options.exif)
                        Toggle("IPTC — current caption, keywords and rating", isOn: $options.iptc)
                        Toggle("GPS — original location", isOn: $options.gps)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                Text("Unchecked metadata is omitted. Original files always retain their embedded metadata.").font(.caption).foregroundStyle(.secondary)
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
                    DispatchQueue.main.async { model.exportWithOptions(selected) }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(invalid)
            }
        }.padding(26).frame(width: 510)
            .onAppear { options = (try? JSONDecoder().decode(ExportOptions.self, from: lastOptions)) ?? ExportOptions() }
    }
    var invalid: Bool { options.format != .original && !(0...100000).contains(options.maxDimension) }
    func save(_ all: [ExportPreset]) { savedPresets = (try? JSONEncoder().encode(all)) ?? Data() }
}
