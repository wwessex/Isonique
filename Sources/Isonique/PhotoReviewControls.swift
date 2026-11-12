import SwiftUI
import IsoniqueCore

enum ColorLabelFilter: Hashable {
    case all
    case unlabelled
    case color(PhotoColorLabel)

    func includes(_ photo: Photo) -> Bool {
        switch self {
        case .all: return true
        case .unlabelled: return photo.colorLabel == nil
        case .color(let label): return photo.colorLabel == label
        }
    }
}

extension PhotoColorLabel {
    var localizedTitle: String { Bundle.main.localizedString(forKey: title, value: nil, table: nil) }

    var tint: Color {
        switch self {
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .green: return .green
        case .blue: return .blue
        case .purple: return .purple
        case .gray: return .gray
        }
    }
}

extension Workspace {
    var canReviewSelection: Bool {
        !busy && !isViewingTrash && (batchMode ? !batchPhotos.isEmpty : selected != nil)
    }

    private func applyReviewChange(_ change: (inout Photo) -> Void) {
        guard canReviewSelection else { return }
        if batchMode {
            editBatch(change)
            return
        }
        let index = photos.firstIndex { $0.id == selection } ?? 0
        edit(change)
        if selected == nil {
            let remaining = photos
            selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
            if remaining.isEmpty { viewer = false }
        }
    }

    func setColorLabel(_ label: PhotoColorLabel?) {
        applyReviewChange { $0.colorLabel = label }
    }

    func setReviewRating(_ rating: Int) {
        applyReviewChange { $0.rating = rating }
    }

    func adjustReviewRating(by delta: Int) {
        applyReviewChange { $0.rating = RatingRules.adjusting($0.rating, by: delta) }
    }

    func toggleReviewFlag() {
        let flagged = batchMode ? !batchPhotos.allSatisfy(\.flagged) : selected?.flagged != true
        applyReviewChange { $0.flagged = flagged }
    }

    func reviewKey(_ press: KeyPress) -> KeyPress.Result {
        guard !busy, !isViewingTrash, tool == .select,
              press.modifiers.intersection([.command, .option, .control, .shift]).isEmpty else { return .ignored }
        switch press.key {
        case .leftArrow, .rightArrow:
            guard !batchMode, !photos.isEmpty else { return .ignored }
            if comparisonID != nil {
                moveComparisonSelection(by: press.key == .leftArrow ? -1 : 1)
                return .handled
            }
            let visible = photos.filter { $0.id != comparisonID }
            if let index = visible.firstIndex(where: { $0.id == selection }) {
                let next = index + (press.key == .leftArrow ? -1 : 1)
                if visible.indices.contains(next) { selection = visible[next].id }
            } else {
                selection = visible.first?.id
            }
        default:
            guard canReviewSelection else { return .ignored }
            switch press.characters {
            case "0", "1", "2", "3", "4", "5":
                if let rating = Int(press.characters) { setReviewRating(rating) }
            case "9": setReviewRating(RatingRules.rejected)
            case "=": adjustReviewRating(by: 1)
            case "-": adjustReviewRating(by: -1)
            case "/": toggleReviewFlag()
            default: return .ignored
            }
        }
        return .handled
    }

    func customName(for label: PhotoColorLabel) -> String {
        labelNames[String(label.rawValue)] ?? ""
    }

    func name(for label: PhotoColorLabel) -> String {
        let name = customName(for: label).trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? label.localizedTitle : name
    }

    func rename(_ label: PhotoColorLabel, to value: String) {
        labelNames[String(label.rawValue)] = value.isEmpty ? nil : value
        preferences.set(labelNames, forKey: "photo.labelNames")
    }
}

struct ColorLabelMenu: View {
    @EnvironmentObject var model: Workspace

    var body: some View {
        Menu("Color Label") {
            Button("Clear Label") { model.setColorLabel(nil) }
            ForEach(PhotoColorLabel.allCases) { label in
                Button { model.setColorLabel(label) } label: {
                    Label(model.name(for: label), systemImage: "circle.fill").foregroundStyle(label.tint)
                }
            }
        }
    }
}

struct ReviewSettingsView: View {
    @EnvironmentObject var model: Workspace

    var body: some View {
        Form {
            ClippingSettingsSection()
            AutoLevelsSettingsSection()
            Section("Color Labels") {
                ForEach(PhotoColorLabel.allCases) { label in
                    TextField(label.localizedTitle, text: Binding(get: { model.customName(for: label) }, set: { model.rename(label, to: $0) }),
                              prompt: Text(label.localizedTitle))
                }
                Text("Names apply across your Isonique libraries. The photo retains its color when you rename a label.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Browser") {
                Picker("Layout", selection: Binding(get: { model.browserLayout }, set: model.setBrowserLayout)) {
                    Text(BrowserPresentation.grid.rawValue).tag(BrowserPresentation.grid)
                    Text(BrowserPresentation.list.rawValue).tag(BrowserPresentation.list)
                }
                GridThumbnailSizePicker(model: model)
            }
            Section("Workspace Controls") {
                Button("Customize Toolbar…") { model.showToolbarEditor = true }
                Button("Keyboard Command Editor…") { model.showCommandEditor = true }
                LabeledContent("Command Set", value: model.activeKeyboardCommandSet.name)
                Text("Toolbar and command-set preferences apply across libraries. Photo recipes and exports are unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("External Editor") {
                LabeledContent("Application", value: model.externalEditorName)
                HStack {
                    Button("Choose Application…", action: model.chooseExternalEditor)
                    if model.externalEditorURL != nil {
                        Button("Clear") { model.setExternalEditor(nil) }
                    }
                }
                Text("Isonique sends a rendered TIFF and imports the saved return as a new managed derivative. The source original remains unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Photo Review Keys") {
                LabeledContent("Rating", value: "0–5")
                LabeledContent("Reject", value: "9")
                LabeledContent("Raise / Lower", value: "= / −")
                LabeledContent("Flag or unflag", value: "/")
                LabeledContent("Previous / Next", value: "← / → in Grid and Viewer, ↑ / ↓ in List")
                Text("Click a photo to focus the Browser or Viewer before using the review keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).frame(width: 470, height: 600)
    }
}
