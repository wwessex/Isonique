import CoreGraphics
import Foundation
import IsoniqueCore

actor ThumbnailCache {
    struct Request: Equatable {
        let photoID: UUID
        let url: URL
        let adjustments: Adjustments
        let maximum: Int
        let revision: Int

        fileprivate var slot: Slot { Slot(photoID: photoID, url: url, maximum: maximum) }
    }

    fileprivate struct Slot: Hashable {
        let photoID: UUID
        let url: URL
        let maximum: Int
    }

    private struct Entry {
        let request: Request
        let stamp: OriginalFileStamp
        let image: CGImage
        let cost: Int
        var use: UInt64
    }

    private struct Job {
        let id = UUID()
        let request: Request
        let stamp: OriginalFileStamp?
        var waiters: [UUID: CheckedContinuation<CGImage, Error>]
        var task: Task<Void, Never>?
    }

    private let byteLimit: Int
    private let workerLimit: Int
    private let render: @Sendable (Request) throws -> CGImage
    private var entries: [Slot: Entry] = [:]
    private var jobs: [Job] = []
    private var running = 0
    private var bytes = 0
    private var use: UInt64 = 0

    init(byteLimit: Int = 64 * 1024 * 1024, workerLimit: Int = 3,
         render: @escaping @Sendable (Request) throws -> CGImage = {
             try Renderer.thumbnail($0.url, adjustments: $0.adjustments, maxDimension: $0.maximum)
         }) {
        self.byteLimit = max(0, byteLimit)
        self.workerLimit = max(1, workerLimit)
        self.render = render
    }

    func image(for request: Request) async throws -> CGImage {
        try Task.checkCancellation()
        let stamp = OriginalFileStamp(request.url)
        if let stamp, var entry = entries[request.slot], entry.stamp == stamp, entry.request == request {
            use &+= 1
            entry.use = use
            entries[request.slot] = entry
            return entry.image
        }
        let waiter = UUID()
        let image: CGImage = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CGImage, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                if let index = jobs.firstIndex(where: { $0.request == request && $0.stamp == stamp && !$0.waiters.isEmpty }) {
                    jobs[index].waiters[waiter] = continuation
                } else {
                    jobs.append(Job(request: request, stamp: stamp, waiters: [waiter: continuation]))
                    startWaitingJobs()
                }
            }
        } onCancel: {
            Task { await self.cancel(waiter) }
        }
        try Task.checkCancellation()
        return image
    }

    private func startWaitingJobs() {
        while running < workerLimit, let index = jobs.firstIndex(where: { $0.task == nil }) {
            let id = jobs[index].id
            let request = jobs[index].request
            let render = self.render
            running += 1
            jobs[index].task = Task.detached(priority: .utility) {
                let result = Result {
                    try Task.checkCancellation()
                    return try render(request)
                }
                await self.finish(id, with: result)
            }
        }
    }

    private func cancel(_ waiter: UUID) {
        guard let index = jobs.firstIndex(where: { $0.waiters[waiter] != nil }) else { return }
        jobs[index].waiters.removeValue(forKey: waiter)?.resume(throwing: CancellationError())
        guard jobs[index].waiters.isEmpty else { return }
        if let task = jobs[index].task {
            task.cancel()
        } else {
            jobs.remove(at: index)
        }
    }

    private func finish(_ id: UUID, with result: Result<CGImage, Error>) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        let job = jobs.remove(at: index)
        running -= 1
        var delivered = result
        if !job.waiters.isEmpty, let stamp = job.stamp, case .success(let image) = result {
            if OriginalFileStamp(job.request.url) == stamp {
                insert(image, for: job.request, stamp: stamp)
            } else {
                delivered = .failure(LibraryError.integrity("original changed while rendering thumbnail"))
            }
        }
        for continuation in job.waiters.values { continuation.resume(with: delivered) }
        startWaitingJobs()
    }

    private func insert(_ image: CGImage, for request: Request, stamp: OriginalFileStamp) {
        // An edited crop may retain its full thumbnail backing.
        guard (1...4096).contains(request.maximum) else { return }
        let stride = max(image.bytesPerRow, (request.maximum * 4 + 63) / 64 * 64)
        let (cost, overflow) = stride.multipliedReportingOverflow(by: request.maximum)
        guard !overflow, cost > 0, cost <= byteLimit else { return }
        if let previous = entries.removeValue(forKey: request.slot) { bytes -= previous.cost }
        while bytes > byteLimit - cost || entries.count >= 512 {
            guard let oldest = entries.min(by: { $0.value.use < $1.value.use })?.key,
                  let removed = entries.removeValue(forKey: oldest) else { break }
            bytes -= removed.cost
        }
        use &+= 1
        entries[request.slot] = Entry(request: request, stamp: stamp, image: image, cost: cost, use: use)
        bytes += cost
    }
}
