import SwiftUI
import AppKit
import IsoniqueCore
import UniformTypeIdentifiers

typealias ExternalEditorLaunch = @MainActor (URL, URL) async throws -> Void

extension Workspace {
    static let externalEditorPreferenceKey = "externalEditor.applicationPath"

    var externalEditorURL: URL? {
        guard let path = preferences.string(forKey: Self.externalEditorPreferenceKey) else { return nil }
        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    var externalEditorName: String {
        externalEditorURL?.deletingPathExtension().lastPathComponent ?? "Not selected"
    }

    var canEditExternally: Bool {
        !busy && !batchMode && !isViewingTrash && !quickPreview && externalEditHandoff == nil &&
            selected != nil && repository != nil
    }

    func chooseExternalEditor() {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = "Choose External Photo Editor"
        panel.prompt = "Choose Editor"
        panel.message = "Choose a macOS application that can open and save TIFF files."
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let current = externalEditorURL {
            panel.directoryURL = current.deletingLastPathComponent()
            panel.nameFieldStringValue = current.lastPathComponent
        } else {
            panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        setExternalEditor(url)
    }

    func setExternalEditor(_ url: URL?) {
        if let url {
            preferences.set(url.standardizedFileURL.path, forKey: Self.externalEditorPreferenceKey)
        } else {
            preferences.removeObject(forKey: Self.externalEditorPreferenceKey)
        }
    }

    func editWithExternalEditor(photoID: UUID? = nil) {
        guard !busy, !batchMode, !isViewingTrash, externalEditHandoff == nil,
              let repository,
              let photo = (photoID.flatMap { id in library.photos.first { $0.id == id } }) ?? selected else { return }
        if externalEditorURL == nil { chooseExternalEditor() }
        guard let applicationURL = externalEditorURL else { return }
        startExternalEdit(photo, repository: repository, applicationURL: applicationURL,
                          launch: Self.openInExternalEditor)
    }

    func startExternalEdit(_ photo: Photo, repository: LibraryRepository, applicationURL: URL,
                           launch: @escaping ExternalEditorLaunch) {
        guard !busy, externalEditHandoff == nil else { return }
        busy = true
        status = "Preparing full-resolution TIFF for \(applicationURL.deletingPathExtension().lastPathComponent)…"
        Task {
            do {
                let handoff = try await Task.detached(priority: .userInitiated) {
                    try repository.beginExternalEdit(photo)
                }.value
                do {
                    try await launch(handoff.fileURL, applicationURL)
                } catch {
                    try? repository.cancelExternalEdit(handoff)
                    throw error
                }
                externalEditHandoff = handoff
                status = "Editing \(photo.displayName) externally · save the TIFF, then return to Isonique"
            } catch {
                self.error = error.localizedDescription
                status = "External editor handoff failed"
            }
            busy = false
        }
    }

    func importExternalEdit(_ handoff: ExternalEditHandoff) {
        guard handoff.id == externalEditHandoff?.id, let repository, !busy else { return }
        busy = true
        status = "Checking and importing external edit…"
        let currentLibrary = library
        Task {
            do {
                let result = try await Task.detached(priority: .userInitiated) {
                    try repository.finishExternalEdit(handoff, in: currentLibrary)
                }.value
                library = result.library
                externalEditHandoff = nil
                revealVersion(result.photo.id)
                status = "Imported \(result.photo.displayName) · source original preserved"
            } catch {
                self.error = error.localizedDescription
                status = "External edit not imported"
            }
            busy = false
        }
    }

    func cancelExternalEdit(_ handoff: ExternalEditHandoff) {
        guard handoff.id == externalEditHandoff?.id, let repository, !busy else { return }
        do {
            try repository.cancelExternalEdit(handoff)
            externalEditHandoff = nil
            status = "External edit cancelled · source original preserved"
        } catch {
            self.error = error.localizedDescription
        }
    }

    @MainActor private static func openInExternalEditor(_ fileURL: URL, _ applicationURL: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            NSWorkspace.shared.open([fileURL], withApplicationAt: applicationURL,
                                    configuration: configuration) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}

struct ExternalEditReturnView: View {
    @EnvironmentObject private var model: Workspace
    let handoff: ExternalEditHandoff

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("External Edit", systemImage: "arrow.up.forward.app")
                .font(.title2.bold())
            Text("Save the TIFF in \(model.externalEditorName), then return here. Isonique will verify the file and import it as a new managed derivative. The source original and its edit recipe remain unchanged.")
                .fixedSize(horizontal: false, vertical: true)
            LabeledContent("Return file", value: handoff.fileURL.lastPathComponent)
                .font(.caption)
            HStack {
                Button("Cancel") { model.cancelExternalEdit(handoff) }
                    .disabled(model.busy)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
                Button("Import Edited Version") { model.importExternalEdit(handoff) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.busy)
            }
        }
        .padding(24)
        .frame(width: 500)
        .interactiveDismissDisabled(true)
    }
}
