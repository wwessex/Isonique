import Foundation

/// One connection's initial catalogue and the operations for a single shutter request.
/// The transport finishes the stream when it has delivered the shot's companions.
public struct TetheredCameraConnection: Sendable {
    let initialCatalogue: [CameraImportFile]
    let capture: @Sendable () async throws -> AsyncThrowingStream<CameraImportFile, Error>
    let download: @Sendable (CameraImportFile, URL) async throws -> Void

    public init(initialCatalogue: [CameraImportFile],
                capture: @escaping @Sendable () async throws -> AsyncThrowingStream<CameraImportFile, Error>,
                download: @escaping @Sendable (CameraImportFile, URL) async throws -> Void) {
        self.initialCatalogue = initialCatalogue
        self.capture = capture
        self.download = download
    }
}

public struct TetheredCaptureResult {
    public let library: Library
    public let report: ImportReport
}

public enum TetheredCaptureError: LocalizedError {
    case busy, alreadyConnected

    public var errorDescription: String? {
        switch self {
        case .busy: return "Wait for the current shot to finish or cancel."
        case .alreadyConnected: return "Disconnect the current camera before connecting another one."
        }
    }
}

public actor TetheredCaptureSession {
    private var connection: TetheredCameraConnection?
    private var handled: Set<CameraImportFile> = []
    private var shot: Task<(TetheredCaptureResult, Set<CameraImportFile>), Never>?

    public init() {}

    public func connect(_ camera: TetheredCameraConnection) throws {
        guard shot == nil else { throw TetheredCaptureError.busy }
        guard connection == nil else { throw TetheredCaptureError.alreadyConnected }
        connection = camera
        handled = Set(camera.initialCatalogue)
    }

    public func cancel() {
        shot?.cancel()
    }

    public func disconnect() {
        connection = nil
        handled.removeAll()
        cancel()
    }

    public func capture(repository: LibraryRepository, library: Library, options: ImportOptions = ImportOptions(),
                        projectID: UUID? = nil, albumID: UUID? = nil) async throws -> TetheredCaptureResult {
        guard shot == nil else { throw TetheredCaptureError.busy }
        guard let connection else { throw DeviceImportError.disconnected }
        let alreadyHandled = handled
        let task = Task.detached(priority: .userInitiated) {
            var draft = library
            var arrivals: Set<CameraImportFile> = []
            let report: ImportReport
            do {
                try Task.checkCancellation()
                let events = try await connection.capture()
                for try await file in events {
                    try Task.checkCancellation()
                    if (file.isPhoto || file.isSidecar), !alreadyHandled.contains(file) {
                        arrivals.insert(file)
                    }
                }
                try Task.checkCancellation()
                if arrivals.contains(where: \.isPhoto) {
                    report = await ImportJob.run(cameraFiles: Array(arrivals), options: options,
                        repository: repository, projectID: projectID, albumID: albumID, into: &draft,
                        download: connection.download)
                } else {
                    report = ImportReport()
                }
            } catch {
                report = ImportReport(sourceError: error)
            }
            return (TetheredCaptureResult(library: draft, report: report), arrivals)
        }
        shot = task
        defer { shot = nil }
        let (result, arrivals) = await withTaskCancellationHandler {
            await task.value
        } onCancel: { task.cancel() }

        // An interrupted batch can be replayed. The importer checks any committed files by digest.
        if self.connection != nil, !result.report.cancelled, result.report.errors.isEmpty {
            handled.formUnion(arrivals)
        }
        return result
    }
}
