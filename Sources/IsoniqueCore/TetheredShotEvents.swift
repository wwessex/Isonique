import Foundation

/// Groups one remote shot from a transport that reports file additions without an end-of-shot event.
@MainActor
public final class TetheredShotEvents {
    public let stream: AsyncThrowingStream<CameraImportFile, Error>
    public private(set) var completed = false
    public private(set) var isCollecting = true

    private let continuation: AsyncThrowingStream<CameraImportFile, Error>.Continuation
    private let baseline: Set<[String]>
    private let baselinePhotoKeys: Set<String>
    private let quietPeriod: Duration
    private var shotKey: String?
    private var files: [[String]: CameraImportFile] = [:]
    private var pendingSidecars: [CameraImportFile] = []
    private var deadline: Task<Void, Never>?
    private var settling: Task<Void, Never>?

    public init(baseline: some Swift.Collection<CameraImportFile>, quietPeriod: Duration = .seconds(2),
                deadline: Duration = .seconds(30)) {
        (stream, continuation) = AsyncThrowingStream.makeStream()
        self.baseline = Set(baseline.map(\.components))
        baselinePhotoKeys = Set(baseline.lazy.filter(\.isPhoto).map { ImportOptions.key($0.logicalURL) })
        self.quietPeriod = quietPeriod
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.fail(CancellationError()) }
        }
        self.deadline = Task { [weak self] in
            do { try await Task.sleep(for: deadline) } catch { return }
            self?.fail(DeviceImportError.timedOut)
        }
    }

    public func receive(_ arrivals: [CameraImportFile]) {
        guard isCollecting else { return }
        var addedFile = false
        for file in arrivals where !baseline.contains(file.components) {
            let key = ImportOptions.key(file.logicalURL)
            // A late companion for an earlier photo must not start the next shot.
            guard !baselinePhotoKeys.contains(key) else { continue }
            if shotKey == nil {
                if file.isSidecar {
                    pendingSidecars.append(file)
                    continue
                }
                guard file.isPhoto else { continue }
                shotKey = key
                for sidecar in pendingSidecars where ImportOptions.key(sidecar.logicalURL) == key {
                    files[sidecar.components] = sidecar
                }
                pendingSidecars.removeAll()
            }
            guard shotKey == key, file.isPhoto || file.isSidecar else { continue }
            let previous = files.updateValue(file, forKey: file.components)
            addedFile = addedFile || previous == nil
        }
        guard addedFile else { return }
        settling?.cancel()
        settling = Task { [weak self, quietPeriod] in
            do { try await Task.sleep(for: quietPeriod) } catch { return }
            guard !Task.isCancelled else { return }
            self?.finish()
        }
    }

    public func fail(_ error: Error) {
        finish(error)
    }

    private func finish(_ error: Error? = nil) {
        guard isCollecting else { return }
        isCollecting = false
        completed = error == nil
        settling?.cancel()
        deadline?.cancel()
        if let error {
            continuation.finish(throwing: error)
        } else {
            for file in files.values { continuation.yield(file) }
            continuation.finish()
        }
        files.removeAll()
        pendingSidecars.removeAll()
    }
}
