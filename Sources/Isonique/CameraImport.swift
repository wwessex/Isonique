import AppKit
import ImageIO
@preconcurrency import ImageCaptureCore
import IsoniqueCore

enum DeviceImportSelection {
    case memoryCard(MemoryCardSource, [URL])
    case camera(CameraImportSession, catalogue: [CameraImportFile], selected: Set<CameraImportFile>)

    @MainActor var name: String {
        switch self {
        case .memoryCard(let card, _): return card.name
        case .camera(let session, _, _): return session.camera.name ?? "Camera"
        }
    }

    var count: Int {
        switch self {
        case .memoryCard(_, let files): return files.count
        case .camera(_, _, let selected): return selected.count
        }
    }

    @MainActor func close() {
        if case .camera(let session, _, _) = self { session.close() }
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

enum NativeTetherError: LocalizedError {
    case remoteShutterUnavailable, reconnectRequired

    static func supportsRemoteShutter(_ capabilities: [String]) -> Bool {
        capabilities.contains(ICDeviceCapability.cameraDeviceCanTakePicture.rawValue)
    }

    var errorDescription: String? {
        switch self {
        case .remoteShutterUnavailable: return "This camera does not report support for taking a picture from the Mac."
        case .reconnectRequired: return "Reconnect the camera before taking another shot."
        }
    }
}

@MainActor final class CameraImportSession: NSObject, ICCameraDeviceDelegate {
    let camera: ICCameraDevice
    private var opening: CameraRequest?
    private var thumbnails: [UUID: CameraRequest] = [:]
    private var previewing = true
    private var transfer: CameraRequest?
    private var downloadProgress: Progress?
    private var files: [CameraImportFile: ICCameraFile] = [:]
    private var removed = false
    private var closed = false
    private var requestedSession = false
    private var tethering = false
    private var shot: TetheredShotEvents?

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
                    else if self.closed, self.camera.delegate == nil {
                        self.closeSession()
                    }
                }
            }
        }
        try Task.checkCancellation()
        return register(camera.mediaFiles ?? [])
    }

    func tetheredConnection() async throws -> TetheredCameraConnection {
        let baseline = try await catalogue()
        guard NativeTetherError.supportsRemoteShutter(camera.capabilities) else {
            throw NativeTetherError.remoteShutterUnavailable
        }
        tethering = true
        return TetheredCameraConnection(initialCatalogue: baseline, capture: { try await self.capture() },
                                        download: { try await self.download($0, to: $1) })
    }

    var tetherNeedsReconnect: Bool {
        removed || closed || !camera.hasOpenSession ||
            !NativeTetherError.supportsRemoteShutter(camera.capabilities) ||
            shot.map { !$0.isCollecting && !$0.completed } == true
    }

    private func capture() throws -> AsyncThrowingStream<CameraImportFile, Error> {
        try Task.checkCancellation()
        guard tethering, !closed, !removed, camera.hasOpenSession else { throw DeviceImportError.disconnected }
        guard NativeTetherError.supportsRemoteShutter(camera.capabilities) else {
            throw NativeTetherError.remoteShutterUnavailable
        }
        if let shot {
            guard !shot.isCollecting else { throw TetheredCaptureError.busy }
            // A failed shutter may still deliver files. Start a fresh camera session before another request.
            guard shot.completed else { throw NativeTetherError.reconnectRequired }
        }
        let shot = TetheredShotEvents(baseline: files.keys)
        self.shot = shot
        camera.requestTakePicture()
        return shot.stream
    }

    private func register(_ items: [ICCameraItem]) -> [CameraImportFile] {
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
        for file in items.compactMap({ $0 as? ICCameraFile }) { add(file) }
        return records
    }

    func thumbnail(for item: CameraImportFile) async throws -> CGImage {
        guard previewing, !removed, !closed, let file = files[item] else {
            throw DeviceImportError.disconnected
        }
        let id = UUID()
        let request = CameraRequest()
        thumbnails[id] = request
        defer { thumbnails[id] = nil }
        var data: Data?
        try await request.wait(seconds: 12, interrupt: {}) {
            file.requestThumbnailData(options: nil) { bytes, error in
                Task { @MainActor in
                    data = bytes
                    request.finish(error)
                }
            }
        }
        try Task.checkCancellation()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard let data, let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LibraryError.unsupportedImage(item.filename)
        }
        return image
    }

    func endPreview() {
        previewing = false
        for request in thumbnails.values { request.finish(CancellationError()) }
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
        if endSession() { closeSession() }
    }

    func closeTetheredConnection() async {
        guard endSession() else { return }
        let request = CameraRequest()
        try? await request.wait(seconds: 8, interrupt: {}) {
            self.camera.requestCloseSession(options: nil) { error in
                Task { @MainActor in request.finish(error) }
            }
        }
    }

    private func endSession() -> Bool {
        guard !closed else { return false }
        closed = true
        endPreview()
        shot?.fail(DeviceImportError.disconnected)
        opening?.finish(DeviceImportError.disconnected)
        if transfer?.finish(DeviceImportError.disconnected) == true {
            downloadProgress?.cancel()
            camera.cancelDownload()
        }
        let ownsDelegate = camera.delegate === self
        if ownsDelegate { camera.delegate = nil }
        files = [:]
        return ownsDelegate && requestedSession
    }

    private func closeSession() {
        camera.requestCloseSession(options: nil) { _ in }
    }

    private func disconnect() {
        removed = true
        endPreview()
        shot?.fail(DeviceImportError.disconnected)
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

    nonisolated func device(_ device: ICDevice, didEncounterError error: Error?) {
        if let error { Task { @MainActor in shot?.fail(error) } }
    }

    nonisolated func cameraDevice(_ camera: ICCameraDevice, didAdd items: [ICCameraItem]) {
        Task { @MainActor in
            guard tethering, !closed, !removed else { return }
            let arrivals = register(items)
            shot?.receive(arrivals)
        }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRemove items: [ICCameraItem]) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didRenameItems items: [ICCameraItem]) {}
    nonisolated func cameraDeviceDidChangeCapability(_ camera: ICCameraDevice) {
        Task { @MainActor in
            if !NativeTetherError.supportsRemoteShutter(camera.capabilities) {
                shot?.fail(NativeTetherError.remoteShutterUnavailable)
            }
        }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceivePTPEvent eventData: Data) {}
    nonisolated func cameraDeviceDidRemoveAccessRestriction(_ device: ICDevice) {}
    nonisolated func cameraDeviceDidEnableAccessRestriction(_ device: ICDevice) {
        Task { @MainActor in
            shot?.fail(DeviceImportError.accessRestricted)
            opening?.finish(DeviceImportError.accessRestricted)
            transfer?.finish(DeviceImportError.accessRestricted)
        }
    }
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveThumbnail thumbnail: CGImage?, for item: ICCameraItem, error: Error?) {}
    nonisolated func cameraDevice(_ camera: ICCameraDevice, didReceiveMetadata metadata: [AnyHashable: Any]?, for item: ICCameraItem, error: Error?) {}
}
