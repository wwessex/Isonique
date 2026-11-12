import SwiftUI
import IsoniqueCore

enum AdjustmentPresetPreferences {
    static let key = "adjustment.presets.v1"

    static func load(from preferences: UserDefaults) -> [CustomAdjustmentPreset] {
        guard let data = preferences.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CustomAdjustmentPreset].self, from: data) else { return [] }
        var names: Set<String> = []
        return decoded.filter { preset in
            let clean = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return !clean.isEmpty && !preset.groups.isEmpty && names.insert(clean.lowercased()).inserted
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct AdjustmentPresetApplicationReview: Identifiable {
    let id = UUID()
    let preset: CustomAdjustmentPreset
    let photoIDs: [UUID]
}

extension Workspace {
    @discardableResult
    func createAdjustmentPreset(named name: String, adjustments: Adjustments,
                                groups: Set<AdjustmentGroup>) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !groups.isEmpty,
              !adjustmentPresets.contains(where: { $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame })
        else { return false }
        var presets = adjustmentPresets
        presets.append(CustomAdjustmentPreset(name: clean, adjustments: adjustments, groups: groups))
        return storeAdjustmentPresets(presets)
    }

    @discardableResult
    func updateAdjustmentPreset(_ id: UUID, adjustments: Adjustments,
                                groups: Set<AdjustmentGroup>) -> Bool {
        guard !groups.isEmpty, var preset = adjustmentPresets.first(where: { $0.id == id }) else { return false }
        preset.adjustments = adjustments
        preset.groups = groups
        return storeAdjustmentPresets(adjustmentPresets.map { $0.id == id ? preset : $0 })
    }

    @discardableResult
    func renameAdjustmentPreset(_ id: UUID, to name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty,
              !adjustmentPresets.contains(where: {
                  $0.id != id && $0.name.localizedCaseInsensitiveCompare(clean) == .orderedSame
              }), var preset = adjustmentPresets.first(where: { $0.id == id }) else { return false }
        preset.name = clean
        return storeAdjustmentPresets(adjustmentPresets.map { $0.id == id ? preset : $0 })
    }

    func deleteAdjustmentPreset(_ id: UUID) {
        _ = storeAdjustmentPresets(adjustmentPresets.filter { $0.id != id })
    }

    func previewAdjustmentPreset(_ preset: CustomAdjustmentPreset) {
        guard !busy, !isViewingTrash, !quickPreview else { return }
        let targets = batchMode ? batchPhotos : selected.map { [$0] } ?? []
        guard !targets.isEmpty else { return }
        adjustmentPresetReview = AdjustmentPresetApplicationReview(preset: preset, photoIDs: targets.map(\.id))
    }

    func applyAdjustmentPreset(_ review: AdjustmentPresetApplicationReview) {
        guard adjustmentPresetReview?.id == review.id, !busy, !isViewingTrash else { return }
        let ids = Set(review.photoIDs)
        var draft = library
        let previous = draft.updatePhotos(ids) { photo in
            photo.adjustments = review.preset.applying(to: photo.adjustments)
        }
        adjustmentPresetReview = nil
        guard commitPhotoChanges(draft, previous: previous) else {
            status = "Selected photos already match \(review.preset.name)"
            return
        }
        status = "Applied \(review.preset.name) to \(previous.count) photo\(previous.count == 1 ? "" : "s") · Undo restores one photo at a time"
    }

    private func storeAdjustmentPresets(_ presets: [CustomAdjustmentPreset]) -> Bool {
        let sorted = presets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard let data = try? JSONEncoder().encode(sorted) else { return false }
        preferences.set(data, forKey: AdjustmentPresetPreferences.key)
        adjustmentPresets = sorted
        return true
    }
}

struct AdjustmentPresetManagerView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: UUID?
    @State private var name = ""
    @State private var groups = AdjustmentGroup.nonSpatialGroups
    @State private var message = ""
    @State private var deleteRequested = false

    private var selectedPreset: CustomAdjustmentPreset? {
        selectedID.flatMap { id in model.adjustmentPresets.first { $0.id == id } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Custom Adjustment Presets").font(.title2.bold())
            Text("Save selected groups from the current photo. Spatial adjustments are excluded until you select them.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Preset", selection: $selectedID) {
                Text("New Preset").tag(UUID?.none)
                ForEach(model.adjustmentPresets) { preset in Text(preset.name).tag(Optional(preset.id)) }
            }
            TextField("Preset name", text: $name)
            GroupBox("Adjustment groups") {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                    ForEach(AdjustmentGroup.allCases) { group in
                        Toggle(group.rawValue, isOn: Binding(get: { groups.contains(group) }, set: { included in
                            if included { groups.insert(group) } else { groups.remove(group) }
                        }))
                    }
                }.padding(.top, 4)
            }
            if groups.contains(where: \.isSpatial) {
                Label("This preset includes spatial adjustments and can replace crop, geometry or photo-specific masks.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !message.isEmpty { Text(message).font(.caption).foregroundStyle(.secondary) }
            HStack {
                if selectedPreset == nil {
                    Button("Create Preset", action: create)
                        .disabled(model.selected == nil || cleanName.isEmpty || groups.isEmpty)
                } else {
                    Button("Update from Current Photo", action: update)
                        .disabled(model.selected == nil || groups.isEmpty)
                    Button("Rename", action: rename).disabled(cleanName.isEmpty)
                    Button("Delete", role: .destructive) { deleteRequested = true }
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22).frame(minWidth: 590, minHeight: 520)
        .onAppear { loadSelection() }
        .onChange(of: selectedID) { _, _ in loadSelection() }
        .confirmationDialog("Delete Adjustment Preset?", isPresented: $deleteRequested) {
            Button("Delete", role: .destructive, action: deletePreset)
            Button("Cancel", role: .cancel) {}
        } message: { Text(selectedPreset?.name ?? "") }
    }

    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func loadSelection() {
        if let preset = selectedPreset {
            name = preset.name
            groups = preset.groups
        } else {
            name = ""
            groups = AdjustmentGroup.nonSpatialGroups
        }
        message = ""
    }

    private func create() {
        guard let adjustments = model.selected?.adjustments else { return }
        if model.createAdjustmentPreset(named: name, adjustments: adjustments, groups: groups) {
            selectedID = model.adjustmentPresets.first {
                $0.name.localizedCaseInsensitiveCompare(cleanName) == .orderedSame
            }?.id
            message = "Preset created."
        } else { message = "Use a unique non-empty name and select at least one group." }
    }

    private func update() {
        guard let id = selectedID, let adjustments = model.selected?.adjustments else { return }
        message = model.updateAdjustmentPreset(id, adjustments: adjustments, groups: groups)
            ? "Preset updated from the current photo." : "Preset could not be updated."
    }

    private func rename() {
        guard let id = selectedID else { return }
        message = model.renameAdjustmentPreset(id, to: name)
            ? "Preset renamed." : "Use a unique non-empty name."
        if let preset = model.adjustmentPresets.first(where: { $0.id == id }) { name = preset.name }
    }

    private func deletePreset() {
        guard let id = selectedID else { return }
        model.deleteAdjustmentPreset(id)
        selectedID = nil
        message = "Preset deleted."
    }
}

struct AdjustmentPresetReviewView: View {
    @EnvironmentObject private var model: Workspace
    let review: AdjustmentPresetApplicationReview

    private var photos: [Photo] {
        let byID = Dictionary(uniqueKeysWithValues: model.library.photos.map { ($0.id, $0) })
        return review.photoIDs.compactMap { byID[$0] }
    }

    private var changedPhotos: [Photo] {
        photos.filter { !review.preset.changedGroups(in: $0.adjustments).isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Apply \(review.preset.name)?").font(.title2.bold())
            LabeledContent("Photo versions", value: "\(photos.count)")
            LabeledContent("Will change", value: "\(changedPhotos.count)")
            GroupBox("Selected groups") {
                Text(review.preset.groups.sorted { $0.rawValue < $1.rawValue }.map(\.rawValue).joined(separator: " · "))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if review.preset.includesSpatialAdjustments {
                Label("Spatial groups are selected. Existing crop, geometry or photo-specific masks may be replaced.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            } else {
                Label("Crop, geometry, brush masks, Repair/Clone and red-eye regions will be preserved.",
                      systemImage: "checkmark.shield")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(photos) { photo in
                        let changed = review.preset.changedGroups(in: photo.adjustments)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(photo.displayName)
                            Text(changed.isEmpty ? "No changes" : changed.sorted { $0.rawValue < $1.rawValue }
                                .map(\.rawValue).joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxHeight: 230)
            HStack {
                Button("Cancel") { model.adjustmentPresetReview = nil }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") { model.applyAdjustmentPreset(review) }
                    .keyboardShortcut(.defaultAction).disabled(changedPhotos.isEmpty)
            }
        }.padding(22).frame(minWidth: 560, minHeight: 430)
    }
}
