import AppKit
@preconcurrency import ImageCaptureCore
import SwiftUI
import IsoniqueCore

struct DeviceImportView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var discovery: CameraDiscovery

    @State private var choice: Choice?
    @State private var photos: [DevicePhoto] = []
    @State private var selection: Set<UUID> = []
    @State private var cardCache: ThumbnailCache?
    @State private var cameraSession: CameraImportSession?
    @State private var cameraCatalogue: [CameraImportFile] = []
    @State private var catalogueTask: Task<Void, Never>?
    @State private var loading = false
    @State private var message: String?

    private enum Choice: Hashable {
        case camera(ObjectIdentifier)
        case card(MemoryCardSource)
    }

    private struct DevicePhoto: Identifiable {
        enum File {
            case card(URL)
            case camera(CameraImportFile)
        }

        let id = UUID()
        let file: File
        let path: String
        var name: String { (path as NSString).lastPathComponent }
        var folder: String { (path as NSString).deletingLastPathComponent }
    }

    private var camera: ICCameraDevice? {
        guard case .camera(let id) = choice else { return nil }
        return discovery.cameras.first { ObjectIdentifier($0) == id }
    }

    private var available: Bool {
        switch choice {
        case .camera: return camera != nil
        case .card(let card): return discovery.cards.contains(card)
        case nil: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from Camera or Card").font(.title2.bold())
            Text("Choose a device and select the photos to copy into the library.")
                .foregroundStyle(.secondary)
            HStack {
                Picker("Device", selection: $choice) {
                    Text("Choose a device").tag(nil as Choice?)
                    ForEach(discovery.cameras, id: \.self) { device in
                        Label(device.name ?? "Camera", systemImage: "camera")
                            .tag(Optional(Choice.camera(ObjectIdentifier(device))))
                    }
                    ForEach(discovery.cards) { card in
                        Label(card.name + " (mounted media)", systemImage: "sdcard")
                            .tag(Optional(Choice.card(card)))
                    }
                }
                Button("Refresh") {
                    discovery.refreshCards()
                    if available, !loading, photos.isEmpty { browse() }
                }
            }
            if loading {
                ProgressView("Reading device photos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !photos.isEmpty {
                HStack {
                    Text("\(selection.count) selected of \(photos.count) photos")
                        .monospacedDigit().accessibilityIdentifier("DeviceImportSelectionCount")
                    Spacer()
                    Button("Select All") { selection = Set(photos.map(\.id)) }
                        .disabled(selection.count == photos.count)
                    Button("Deselect All") { selection.removeAll() }
                        .disabled(selection.isEmpty)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 138), spacing: 12)], spacing: 12) {
                        ForEach(photos) { photo in tile(photo) }
                    }.padding(4)
                }
            } else {
                Text(message ?? (discovery.cameras.isEmpty && discovery.cards.isEmpty
                    ? "Connect and unlock a camera in photo transfer mode, or insert a card."
                    : "Choose a camera or card to browse its photos."))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import Options…", action: continueToImport)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!available || loading || selection.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 760, height: 555)
        .onChange(of: choice) { _, value in
            if value == nil { reset() }
            else { browse() }
        }
        .onChange(of: available) { _, connected in
            if !connected, choice != nil { disconnected() }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            discovery.refreshCards()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { notification in
            if case .card(let card) = choice,
               let url = notification.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL,
               card.volume.path == url.path {
                disconnected()
            }
            discovery.refreshCards()
        }
        .onDisappear(perform: reset)
    }

    private func tile(_ photo: DevicePhoto) -> some View {
        let isSelected = selection.contains(photo.id)
        return Toggle(isOn: Binding(get: { selection.contains(photo.id) }, set: { selected in
            if selected { selection.insert(photo.id) }
            else { selection.remove(photo.id) }
        })) {
            VStack(alignment: .leading, spacing: 5) {
                thumbnail(photo)
                    .frame(maxWidth: .infinity).frame(height: 92)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                Text(photo.name).font(.caption).lineLimit(1)
                if !photo.folder.isEmpty {
                    Text(photo.folder).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? Color.accentColor.opacity(0.2) : .clear,
                        in: RoundedRectangle(cornerRadius: 7))
        }
        .toggleStyle(.checkbox)
        .accessibilityLabel(photo.path)
        .help(photo.path)
    }

    @ViewBuilder private func thumbnail(_ photo: DevicePhoto) -> some View {
        switch photo.file {
        case .card(let url):
            if let cardCache {
                Thumbnail(request: .init(photoID: photo.id, url: url, adjustments: Adjustments(),
                                         maximum: 256, revision: 0), cache: cardCache)
            }
        case .camera(let file):
            if let cameraSession { CameraImportThumbnail(session: cameraSession, file: file) }
        }
    }

    private func reset() {
        catalogueTask?.cancel()
        catalogueTask = nil
        cameraSession?.close()
        cameraSession = nil
        cameraCatalogue = []
        cardCache = nil
        photos = []
        selection = []
        loading = false
    }

    private func disconnected() {
        reset()
        choice = nil
        message = "Device disconnected. Reconnect it and choose it again to browse its photos."
    }

    private func browse() {
        reset()
        message = nil
        guard let choice, available else { return }
        loading = true
        switch choice {
        case .card(let card):
            let scan = Task.detached(priority: .userInitiated) { try card.photoFiles() }
            catalogueTask = Task {
                do {
                    let files = try await withTaskCancellationHandler {
                        try await scan.value
                    } onCancel: { scan.cancel() }
                    try Task.checkCancellation()
                    photos = files.map {
                        let relative = $0.pathComponents.dropFirst(card.folder.pathComponents.count).joined(separator: "/")
                        return DevicePhoto(file: .card($0), path: relative)
                    }
                    cardCache = ThumbnailCache(byteLimit: 32 * 1024 * 1024) { request in
                        try card.thumbnail(for: request.url, maximum: request.maximum)
                    }
                    finishCatalogue()
                } catch { catalogueFailed(error) }
            }
        case .camera:
            guard let camera else { disconnected(); return }
            let session = CameraImportSession(camera)
            cameraSession = session
            catalogueTask = Task {
                do {
                    let files = try await session.catalogue()
                    try Task.checkCancellation()
                    cameraCatalogue = files
                    photos = files.filter(\.isPhoto).map {
                        DevicePhoto(file: .camera($0), path: $0.components.joined(separator: "/"))
                    }.sorted { $0.path < $1.path }
                    finishCatalogue()
                } catch { catalogueFailed(error) }
            }
        }
    }

    private func finishCatalogue() {
        loading = false
        if photos.isEmpty { message = DeviceImportError.noPhotos.localizedDescription }
    }

    private func catalogueFailed(_ error: Error) {
        guard !Task.isCancelled else { return }
        reset()
        message = error.localizedDescription
    }

    private func continueToImport() {
        guard let choice, available, !loading, !selection.isEmpty else { return }
        let selected = photos.filter { selection.contains($0.id) }
        switch choice {
        case .card(let card):
            let files = selected.compactMap { photo -> URL? in
                if case .card(let url) = photo.file { return url }
                return nil
            }
            model.pendingDeviceImport = .memoryCard(card, files)
        case .camera:
            guard let session = cameraSession else { return }
            let files = selected.compactMap { photo -> CameraImportFile? in
                if case .camera(let file) = photo.file { return file }
                return nil
            }
            session.endPreview()
            model.pendingDeviceImport = .camera(session, catalogue: cameraCatalogue, selected: Set(files))
            cameraSession = nil
        }
        dismiss()
    }
}

private struct CameraImportThumbnail: View {
    let session: CameraImportSession
    let file: CameraImportFile
    @State private var image: CGImage?

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }.task(id: file) {
            let result = try? await session.thumbnail(for: file)
            if !Task.isCancelled { image = result }
        }.onDisappear { image = nil }
    }
}
