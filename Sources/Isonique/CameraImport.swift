import AppKit
import SwiftUI
@preconcurrency import ImageCaptureCore
import IsoniqueCore

enum DeviceImportSource {
    case memoryCard(MemoryCardSource)
    case camera(ICCameraDevice)

    var name: String {
        switch self {
        case .memoryCard(let card): return card.name
        case .camera(let device): return device.name ?? "Camera"
        }
    }
}

@MainActor final class CameraDiscovery: NSObject, ObservableObject, ICDeviceBrowserDelegate {
    @Published private(set) var cameras: [ICCameraDevice] = []
    @Published private(set) var cards: [MemoryCardSource] = []
    private let browser = ICDeviceBrowser()
    private var scan: Task<Void, Never>?

    func start() {
        guard !browser.isBrowsing else { refreshCards(); return }
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(rawValue:
            ICDeviceTypeMask.camera.rawValue | ICDeviceLocationTypeMask.local.rawValue) ?? .camera
        browser.start()
        refreshCards()
    }

    func stop() {
        browser.stop()
        browser.delegate = nil
        scan?.cancel()
        cameras = []; cards = []
    }

    func refreshCards() {
        scan?.cancel()
        scan = Task {
            let discovered = await Task.detached(priority: .utility) { MemoryCardSource.discover() }.value
            if !Task.isCancelled { cards = discovered }
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice, !device.isRemote else { return }
        Task { @MainActor in
            guard browser.isBrowsing, !cameras.contains(where: { $0 === camera }) else { return }
            cameras.append(camera)
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor in cameras.removeAll { $0 === device } }
    }
}

@MainActor
private final class CameraRequest {
    private var continuation: CheckedContinuation<Void, Error>?
    private var timeout: Task<Void, Never>?

    func wait(seconds: UInt64, interrupt: @escaping @MainActor () -> Void,
              start: @escaping @MainActor () -> Void) async throws {
        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                self.continuation = continuation
                timeout = Task {
                    do { try await Task.sleep(nanoseconds: seconds * 1_000_000_000) }
                    catch { return }
                    if finish(DeviceImportError.timedOut) { interrupt() }
                }
                start()
            }
        } onCancel: {
            Task { @MainActor in if self.finish(CancellationError()) { interrupt() } }
        }
    }

    @discardableResult
    func finish(_ error: Error? = nil) -> Bool {
        guard let continuation else { return false }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        if let error { continuation.resume(throwing: error) }
        else { continuation.resume() }
        return true
    }
}

@MainActor final class CameraImportSession: NSObject, ICCameraDeviceDelegate {
    private let camera: ICCameraDevice
    private var opening: CameraRequest?
    private var transfer: CameraRequest?
    private var downloadProgress: Progress?
    private var files: [CameraImportFile: ICCameraFile] = [:]
    private var removed = false
    private var closed = false
    private var requestedSession = false

    init(_ camera: ICCameraDevice) { self.camera = camera }

    func catalogue() async throws -> [CameraImportFile] {
        let request = CameraRequest()
        opening = request
        defer { opening = nil }
        try await request.wait(seconds: 75, interrupt: { self.close() }) {
            self.camera.delegate = self
            self.requestedSession = true
            self.camera.requestOpenSession(options: nil) { error in
                Task { @MainActor in
                    if let error { request.finish(error) }
                    else if self.closed { self.closeSession() }
                }
            }
        }
        try Task.checkCancellation()
        var seen: Set<ObjectIdentifier> = []
        var records: [CameraImportFile] = []
        func add(_ file: ICCameraFile, inheritedFolders: [String]? = nil) {
            guard seen.insert(ObjectIdentifier(file)).inserted, let name = file.name else { return }
            var folders: [String] = []
            var parent = file.parentFolder
            while let folder = parent {
                guard folders.count < 31, let name = folder.name else { return }
                folders.append(name)
                parent = folder.parentFolder
            }
            let ancestors = folders.isEmpty ? (inheritedFolders ?? []) : Array(folders.reversed())
            guard let entry = CameraImportFile(components: ancestors + [name], byteCount: Int64(file.fileSize)),
                  entry.isPhoto || entry.isSidecar else { return }
            files[entry] = file
            records.append(entry)
            if let raw = file.pairedRawImage { add(raw, inheritedFolders: ancestors) }
            for sidecar in (file.sidecarFiles ?? []).compactMap({ $0 as? ICCameraFile }) { add(sidecar, inheritedFolders: ancestors) }
        }
        for file in (camera.mediaFiles ?? []).compactMap({ $0 as? ICCameraFile }) { add(file) }
        return records
    }

    func download(_ item: CameraImportFile, to destination: URL) async throws {
        guard !removed, !closed, let file = files[item] else { throw DeviceImportError.disconnected }
        let request = CameraRequest()
        transfer = request
        defer { transfer = nil; downloadProgress = nil }
        try await request.wait(seconds: 300, interrupt: {
            self.downloadProgress?.cancel()
            self.camera.cancelDownload()
        }) {
            // All writes go to a private local folder. Never delete, eject or rename camera files.
            self.downloadProgress = file.requestDownload(options: [
                .downloadsDirectoryURL: destination.deletingLastPathComponent(),
                .saveAsFilename: destination.lastPathComponent,
                .overwrite: false,
                .sidecarFiles: false,
                .deleteAfterSuccessfulDownload: false
            ]) { _, error in
                Task { @MainActor in request.finish(error) }
            }
        }
    }

    func close() {
        guard !closed else { return }
        closed = true
        if requestedSession { closeSession() }
        camera.delegate = nil
        files = [:]
    }

    private func closeSession() {
        camera.requestCloseSession(options: nil) { _ in }
    }

    private func disconnect() {
        removed = true
        opening?.finish(DeviceImportError.disconnected)
        transfer?.finish(DeviceImportError.disconnected)
    }

    nonisolated func didRemove(_ device: ICDevice) {
        Task { @MainActor in disconnect() }
    }

    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        if let error { Task { @MainActor in opening?.finish(error) } }
    }

    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {
        Task { @MainActor in if !closed { disconnect() } }
    }

    nonisolated func deviceDidBecomeReady(withCompleteContentCatalog device: ICCameraDevice) {
        Task { @MainActor in opening?.finish() }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in
            opening?.finish(DeviceImportError.accessRestricted)
            transfer?.finish(DeviceImportError.accessRestricted)
        }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
}

struct DeviceImportView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var discovery: CameraDiscovery
    @State private var selected: Choice?
    private enum Choice: Hashable { case camera(ObjectIdentifier), card(URL) }
    private var source: DeviceImportSource? {
        switch selected {
        case .camera(let id): return discovery.cameras.first { ObjectIdentifier($0) == id }.map(DeviceImportSource.camera)
        case .card(let id): return discovery.cards.first { $0.id == id }.map(DeviceImportSource.memoryCard)
        case nil: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import from Camera or Card").font(.title2.bold())
            Text("Choose a connected camera or a mounted card with a DCIM folder. Isonique copies supported photographs into the library and leaves the device unchanged.")
                .foregroundStyle(.secondary)
            if discovery.cameras.isEmpty && discovery.cards.isEmpty {
                Text("No cameras or memory cards found. Connect and unlock the camera in photo transfer mode, or insert a card.")
                    .padding(.vertical, 8)
            } else {
                Picker("Device", selection: $selected) {
                    Text("Choose a device").tag(nil as Choice?)
                    ForEach(discovery.cameras, id: \.self) { device in
                        Label(device.name ?? "Camera", systemImage: "camera").tag(Optional(Choice.camera(ObjectIdentifier(device))))
                    }
                    ForEach(discovery.cards) { card in
                        Label(card.name + " — mounted media", systemImage: "sdcard").tag(Optional(Choice.card(card.id)))
                    }
                }
            }
            HStack {
                Button("Refresh", action: discovery.refreshCards)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Import Options…") {
                    guard let source else { return }
                    model.pendingDeviceImport = source
                    dismiss()
                }.keyboardShortcut(.defaultAction).disabled(source == nil)
            }
        }
        .padding(24).frame(width: 530)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in discovery.refreshCards() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in discovery.refreshCards() }
    }
}
