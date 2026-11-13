import CoreGraphics
import Foundation
import IsoniqueCore

/// Caches the shared renderer's unproofed output for this Workspace only.
actor ViewerRenderCache {
    struct Frame {
        let image: CGImage
        let geometry: PhotoGeometry
        let sourceStamp: OriginalFileStamp?
    }

    private struct Key: Equatable {
        let url: URL
        let stamp: OriginalFileStamp
        let adjustments: Adjustments
        let maximum: CGFloat?
        let revision: Int
    }

    private struct Entry {
        let key: Key
        let frame: Frame
        let bytes: Int
    }

    private let byteLimit: Int
    private let entryLimit = 8
    private var entries: [Entry] = []
    private var bytes = 0

    init(byteLimit: Int = 128 * 1024 * 1024) {
        self.byteLimit = max(0, byteLimit)
    }

    func frame(url: URL, adjustments: Adjustments, maximum: CGFloat?, revision: Int) async throws -> Frame {
        try Task.checkCancellation()
        let key = OriginalFileStamp(url).map {
            Key(url: url, stamp: $0, adjustments: adjustments, maximum: maximum, revision: revision)
        }
        if let key, let index = entries.firstIndex(where: { $0.key == key }) {
            let hit = entries.remove(at: index)
            entries.append(hit)
            return hit.frame
        }
        let render = Task.detached(priority: .userInitiated) {
            let result = try Renderer.renderWithGeometry(url, adjustments: adjustments, maxDimension: maximum)
            return Frame(image: result.image, geometry: result.geometry, sourceStamp: key?.stamp)
        }
        let result = await withTaskCancellationHandler {
            await render.result
        } onCancel: { render.cancel() }
        try Task.checkCancellation()
        let frame = try result.get()
        if let key, OriginalFileStamp(url) == key.stamp {
            insert(frame, for: key)
        }
        return frame
    }

    private func insert(_ frame: Frame, for key: Key) {
        let width = Int(frame.geometry.sourceSize.width), height = Int(frame.geometry.sourceSize.height)
        // A CGImage crop can retain the pre-crop backing store. Charge that extent, including row padding.
        func backingCost(width: Int, height: Int) -> Int {
            let stride = (width * 4 + 63) / 64 * 64
            let (size, overflow) = stride.multipliedReportingOverflow(by: height)
            return overflow ? Int.max : size
        }
        let (outputCost, overflow) = frame.image.bytesPerRow.multipliedReportingOverflow(by: frame.image.height)
        let cost = max(outputCost, backingCost(width: width, height: height),
                       backingCost(width: height, height: width))
        guard !overflow, cost <= byteLimit else { return }
        if let duplicate = entries.firstIndex(where: { $0.key == key }) {
            bytes -= entries.remove(at: duplicate).bytes
        }
        while bytes > byteLimit - cost || entries.count >= entryLimit {
            bytes -= entries.removeFirst().bytes
        }
        entries.append(Entry(key: key, frame: frame, bytes: cost))
        bytes += cost
    }
}
