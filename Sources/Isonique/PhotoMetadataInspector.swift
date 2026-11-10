import IsoniqueCore
import SwiftUI

struct PhotoMetadataInspector: View {
    let photo: Photo

    @EnvironmentObject private var model: Workspace
    @State private var editingView: CustomMetadataView?
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Picker("Metadata View", selection: Binding(get: { model.metadataViews.selection },
                                                           set: model.selectMetadataView)) {
                    ForEach(BuiltInMetadataView.allCases) { view in
                        Text(view.name).tag(MetadataViewSelection.builtIn(view))
                    }
                    if !model.metadataViews.customViews.isEmpty { Divider() }
                    ForEach(model.metadataViews.customViews) { view in
                        Text(view.name).tag(MetadataViewSelection.custom(view.id))
                    }
                }
                Menu {
                    Button("New View…") { editingView = CustomMetadataView(name: "", fields: []) }
                    Button("Duplicate Current View…", action: duplicate)
                    if let view = model.metadataViews.selectedCustomView {
                        Button("Edit Current View…") { editingView = view }
                        Button("Delete Current View…", role: .destructive) { confirmingDelete = true }
                    }
                } label: {
                    Label("Manage Metadata Views", systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                }
                .fixedSize()
            }
            switch model.metadataViews.selection {
            case .builtIn(.general): general
            case .builtIn(let view): fieldList(view.fields)
            case .custom:
                if let view = model.metadataViews.selectedCustomView {
                    fieldList(view.fields).id(view)
                }
            }
        }
        .font(.caption)
        .sheet(item: $editingView) { view in
            MetadataViewEditor(view: view).environmentObject(model)
        }
        .confirmationDialog("Delete Metadata View?", isPresented: $confirmingDelete,
                            presenting: model.metadataViews.selectedCustomView) { view in
            Button("Delete", role: .destructive) { model.deleteMetadataView(view.id) }
        } message: { view in
            Text(view.name)
        }
    }

    private func duplicate() {
        let name: String
        let fields: [MetadataViewField]
        switch model.metadataViews.selection {
        case .builtIn(let view):
            name = view.name
            fields = view.fields
        case .custom:
            guard let view = model.metadataViews.selectedCustomView else { return }
            name = view.name
            fields = view.fields
        }
        editingView = CustomMetadataView(name: String(localized: "\(name) Copy"), fields: fields)
    }

    @ViewBuilder private var general: some View {
        row(.dimensions)
        if !photo.camera.isEmpty { row(.camera) }
        row(.captured)
        row(.imported)
        EXIFInspectorView(photo: photo)
        ratingControls(showFlag: true)
        linkedOriginals
        row(.colorLabel)
        row(.caption)
        row(.keywords)
        keywordPaths
        IPTCInspectorView(photo: photo).id(photo.id)
        row(.originalStorage)
    }

    @ViewBuilder private func fieldList(_ fields: [MetadataViewField]) -> some View {
        if fields.contains(where: \.isEXIF) {
            EXIFMetadataReader(photo: photo) { readout in
                orderedRows(fields, exif: readout)
            }
        } else {
            orderedRows(fields, exif: nil)
        }
    }

    @ViewBuilder private func orderedRows(_ fields: [MetadataViewField], exif: EXIFReadout?) -> some View {
        if fields.contains(where: { $0.iptcField != nil }) {
            IPTCMetadataEditor(photo: photo) { editor in
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(fields) { row($0, exif: exif, editor: editor) }
                    editor.actions
                }
            }.id(photo.id)
        } else {
            ForEach(fields) { row($0, exif: exif) }
        }
    }

    @ViewBuilder private func row(_ field: MetadataViewField, exif: EXIFReadout? = nil,
                                  editor: IPTCFieldEditor? = nil) -> some View {
        switch field {
        case .name:
            LabeledContent(field.label, value: photo.displayName)
        case .dimensions:
            Text("\(photo.width) × \(photo.height) · \((photo.originalName as NSString).pathExtension.uppercased())")
                .foregroundStyle(.secondary)
        case .camera:
            LabeledContent(field.label, value: photo.camera.isEmpty ? String(localized: "Unknown") : photo.camera)
        case .captured:
            LabeledContent(field.label, value: photo.captureDate.isEmpty ? String(localized: "Unknown") : photo.captureDate)
            if !model.batchMode {
                Button("Adjust Date and Time…", action: model.openCaptureDateCorrection)
                    .disabled(!model.canAdjustCaptureDate)
            }
        case .imported:
            LabeledContent(field.label, value: photo.importedAt.formatted(date: .abbreviated, time: .shortened))
        case .rating:
            ratingControls(showFlag: false)
        case .flag:
            Toggle("Flagged", isOn: model.binding(\.flagged, fallback: false))
        case .colorLabel:
            Picker("Color label", selection: model.binding(\.colorLabel, fallback: nil)) {
                Text("No label").tag(nil as PhotoColorLabel?)
                ForEach(PhotoColorLabel.allCases) { label in
                    Label(model.name(for: label), systemImage: "circle.fill").foregroundStyle(label.tint).tag(Optional(label))
                }
            }
        case .caption:
            Text("Caption").foregroundStyle(.secondary)
            TextField("Caption", text: model.binding(\.caption, fallback: ""), axis: .vertical)
        case .keywords:
            Text("Keywords").foregroundStyle(.secondary)
            TextField("Keywords, separated by commas", text: model.binding(\.keywords, fallback: ""))
        case .keywordPaths:
            if photo.keywordPaths?.isEmpty != false {
                LabeledContent(field.label, value: String(localized: "None"))
            } else {
                keywordPaths
            }
        case .title, .creator, .copyright, .credit:
            if let iptcField = field.iptcField, let editor { editor.row(iptcField) }
        case .shutterSpeed, .aperture, .iso, .focalLength, .lens:
            if let exif {
                LabeledContent(field.label, value: exif.value(for: field)).textSelection(.enabled)
            }
        case .originalStorage:
            OriginalInfoView(photo: photo)
        case .linkedOriginal:
            if photo.pairID == nil {
                LabeledContent(field.label, value: String(localized: "None"))
            } else {
                linkedOriginals
            }
        }
    }

    private func ratingControls(showFlag: Bool) -> some View {
        Group {
            HStack(spacing: 6) {
                ForEach(1...RatingRules.maximum, id: \.self) { rating in
                    Button { model.edit { $0.rating = rating } } label: {
                        Image(systemName: photo.rating >= rating ? "star.fill" : "star").foregroundStyle(.orange)
                    }.buttonStyle(.plain).help("Rate \(rating) stars")
                }
                if showFlag {
                    Spacer()
                    Toggle(isOn: model.binding(\.flagged, fallback: false)) { Image(systemName: "flag.fill") }
                        .toggleStyle(.button).help("Flag photograph")
                }
            }
            HStack {
                Toggle("Rejected", isOn: Binding(get: { photo.rating == RatingRules.rejected },
                                                  set: { model.setRejected($0) }))
                Button("Unrated") { model.edit { $0.rating = RatingRules.unrated } }
            }
            HStack {
                Button("Lower Rating") { model.adjustRating(by: -1) }
                    .disabled(photo.rating <= RatingRules.rejected)
                Button("Raise Rating") { model.adjustRating(by: 1) }
                    .disabled(photo.rating >= RatingRules.maximum)
            }
        }
    }

    @ViewBuilder private var linkedOriginals: some View {
        if let pair = photo.pairID {
            Text("Linked RAW + JPEG").foregroundStyle(.secondary)
            let companions = model.library.activePhotos.filter { $0.pairID == pair && $0.originalID != photo.originalID }
            ForEach(companions.filter { candidate in
                candidate.id == (companions.first { $0.originalID == candidate.originalID && $0.id == $0.originalID }
                                 ?? companions.first { $0.originalID == candidate.originalID })?.id
            }) { companion in
                Button("View " + companion.displayName) { model.revealVersion(companion.id) }
            }
        }
    }

    @ViewBuilder private var keywordPaths: some View {
        if let paths = photo.keywordPaths, !paths.isEmpty {
            Text("Vocabulary Keywords").foregroundStyle(.secondary)
            ForEach(paths, id: \.self) { path in
                HStack {
                    Text(path.title)
                    Spacer()
                    Button("Remove \(path.title)", systemImage: "xmark.circle") {
                        model.changeKeywordPath(path, adding: false)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .disabled(model.batchMode)
                }
            }
        }
    }
}

private struct MetadataViewEditor: View {
    let id: UUID

    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var fields: [MetadataViewField]
    @State private var saveFailed = false

    init(view: CustomMetadataView) {
        id = view.id
        _name = State(initialValue: view.name)
        _fields = State(initialValue: view.fields)
    }

    var body: some View {
        let view = CustomMetadataView(id: id, name: name, fields: fields)
        let available = MetadataViewField.allCases.filter { !fields.contains($0) }
        VStack(alignment: .leading, spacing: 12) {
            Text("Configure Metadata View").font(.title2.bold())
            TextField("View name", text: $name)
            Menu("Add Field") {
                ForEach(available) { field in
                    Button(field.label) { fields.append(field) }
                }
            }.disabled(available.isEmpty)
            if fields.isEmpty {
                Text("Add the fields you want to see in Info.").foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(fields.enumerated()), id: \.element) { index, field in
                            HStack {
                                Text(field.label)
                                Spacer()
                                Button("Move \(field.label) up", systemImage: "arrow.up") {
                                    move(field, by: -1)
                                }.disabled(index == 0)
                                Button("Move \(field.label) down", systemImage: "arrow.down") {
                                    move(field, by: 1)
                                }.disabled(index == fields.count - 1)
                                Button("Remove \(field.label)", systemImage: "minus.circle") {
                                    fields.removeAll { $0 == field }
                                }
                            }.labelStyle(.iconOnly)
                        }
                    }.padding(.trailing, 6)
                }.frame(maxHeight: 260)
            }
            if saveFailed {
                Text("The view could not be saved. Choose a different name and try again.")
                    .foregroundStyle(.red)
            } else if !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !fields.isEmpty
                        && !model.metadataViews.accepts(view) {
                Text("A metadata view with this name already exists.").foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save View") {
                    if model.saveMetadataView(view) { dismiss() }
                    else { saveFailed = true }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.metadataViews.accepts(view))
            }
        }.padding(22).frame(width: 430)
    }

    private func move(_ field: MetadataViewField, by offset: Int) {
        guard let index = fields.firstIndex(of: field), fields.indices.contains(index + offset) else { return }
        fields.swapAt(index, index + offset)
    }
}
