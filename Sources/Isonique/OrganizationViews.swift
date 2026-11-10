import SwiftUI
import AppKit
import IsoniqueCore

struct BatchBar: View {
    @EnvironmentObject var model: Workspace
    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                Text("\(model.batchSelection.count) selected").monospacedDigit()
                Button("Select All") { model.batchSelection = Set(model.photos.map(\.id)) }
                Button("Clear") { model.batchSelection = [] }
                if !model.isViewingTrash {
                    Group {
                        Menu("Rating") {
                            ForEach(-1...5, id: \.self) { rating in
                                Button(rating == -1 ? "Rejected" : rating == 0 ? "Unrated" : "\(rating) stars") { model.editBatch { $0.rating = rating } }
                            }
                        }
                        ColorLabelMenu()
                        Menu("Flag") {
                            Button("Flag Selected") { model.editBatch { $0.flagged = true } }
                            Button("Unflag Selected") { model.editBatch { $0.flagged = false } }
                        }
                        Menu("Preset") {
                            ForEach(AdjustmentPreset.allCases) { preset in
                                Button(preset.rawValue) { model.editBatch { $0.adjustments = preset.applying(to: $0.adjustments) } }
                            }
                        }
                        Button("Batch Change…", action: model.openBatchMetadata)
                            .disabled(!model.canOpenBatchMetadata)
                        Button("Stamp", action: model.stamp).disabled(!model.canStamp)
                        Menu("Organize") {
                            Menu("Add to Album") {
                                ForEach(model.library.albums.filter { $0.rule == nil }) { album in
                                    Button(album.name) { model.editBatch { $0.albumIDs.insert(album.id) } }
                                }
                            }
                            Menu("Move to Project") {
                                Button("Unassigned") { model.editBatch { $0.projectID = nil } }
                                ForEach(model.library.projects) { project in
                                    Button(project.name) { model.editBatch { $0.projectID = project.id } }
                                }
                            }
                            Button("Stack Selected", action: model.stackSelection).disabled(!StackRules.canStack(photoCount: model.batchPhotos.count))
                            Button("Remove Selected from Stacks") { model.editBatch { $0.stackID = nil } }
                        }
                        Button("Export Selected…", action: model.exportPanel)
                        Button("Move to Trash") { model.setPhotosTrashed(model.selectedTrashActionIDs, trashed: true) }
                            .disabled(model.selectedTrashActionIDs.isEmpty)
                    }.disabled(model.batchSelection.isEmpty)
                }
            }.padding(12)
        }.scrollIndicators(.hidden).background(.ultraThinMaterial)
    }
}

struct VersionsView: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    @State private var name = ""
    var body: some View {
        DisclosureGroup("Adjustment Snapshots") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Save named adjustments and return to them later. Snapshots change adjustments on this version.").font(.caption).foregroundStyle(.secondary)
                TextField("Snapshot name", text: $name)
                Button("Save Current Adjustments") {
                    let version = PhotoVersion(name: name.trimmingCharacters(in: .whitespacesAndNewlines), adjustments: photo.adjustments)
                    model.edit { $0.versions = ($0.versions ?? []) + [version] }; name = ""
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                ForEach(photo.versions ?? []) { version in
                    VStack(alignment: .leading) {
                        Text(version.name).font(.headline)
                        Text(version.createdAt.formatted()).font(.caption2).foregroundStyle(.secondary)
                        HStack {
                            Button("Restore") { model.tool = .select; model.compareOriginal = false; model.edit { $0.adjustments = version.adjustments } }
                            Button("Delete") { model.edit { $0.versions?.removeAll { $0.id == version.id } } }
                        }
                    }
                }
            }.padding(.top, 10)
        }.id(photo.id)
    }
}

extension Workspace {
    func exportBatch(_ options: ExportOptions) {
        let snapshot = batchPhotos
        guard !busy, !snapshot.isEmpty, let repository else { return }
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "A new Isonique Export folder will hold the selected photos. Originals stay unchanged."
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        // Export enforces managed/legacy library path safety for every destination.
        let folder = parent.appendingPathComponent("Isonique Export \(UUID().uuidString)", isDirectory: true)
        busy = true; status = "Exporting \(snapshot.count) photos…"
        Task {
            let result = await Task.detached { () -> (Int, String?) in
                var count = 0
                do {
                    try BatchExport.prepareDirectory(folder, repository: repository)
                    for (index, photo) in snapshot.enumerated() {
                        let suffix = options.format == .original ? (photo.filename as NSString).pathExtension : options.format.suffix
                        let base = photo.exportBaseName
                        let url = folder.appendingPathComponent("\(index + 1)-\(base).\(suffix)")
                        try Renderer.export(photo, repository: repository, to: url, options: options)
                        count += 1
                    }
                    return (count, nil)
                } catch { return (count, error.localizedDescription) }
            }.value
            busy = false; error = result.1
            status = "Exported \(result.0) of \(snapshot.count) photos" + (result.1 == nil ? " to \(folder.lastPathComponent)" : " · stopped; completed files remain")
        }
    }
}
