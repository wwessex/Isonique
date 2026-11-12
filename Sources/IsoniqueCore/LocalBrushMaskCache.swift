import Foundation

/// A bounded source-space mask cache shared by Viewer, overlays and exports.
///
/// Exact recipes reuse their complete raster. When painting appends strokes to an
/// existing instance, the longest valid cached prefix is copied and only the new
/// suffix is rasterised. Earlier-stroke edits, geometry changes and changes to the
/// decoded pixels used by edge-aware brushes deliberately miss the cache.
final class LocalBrushMaskCache: @unchecked Sendable {
    static let shared = LocalBrushMaskCache()

    struct Statistics: Equatable {
        let exactHits: Int
        let incrementalHits: Int
        let misses: Int
        let rasterizedStrokes: Int
        let evictions: Int
        let entries: Int
        let residentBytes: Int
        let byteLimit: Int
        let entryLimit: Int
    }

    private struct Entry {
        let instanceID: UUID
        let strokes: [LocalBrushStroke]
        let sourceWidth: Int
        let sourceHeight: Int
        let edgeSignature: UInt64?
        let mask: LocalAdjustmentMask
        let bytes: Int
    }

    private let byteLimit: Int
    private let entryLimit: Int
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var residentBytes = 0
    private var exactHits = 0
    private var incrementalHits = 0
    private var misses = 0
    private var rasterizedStrokes = 0
    private var evictions = 0

    init(byteLimit: Int = 128 * 1024 * 1024, entryLimit: Int = 12) {
        self.byteLimit = max(0, byteLimit)
        self.entryLimit = max(0, entryLimit)
    }

    func mask(for instance: LocalBrushInstance, sourceWidth: Int, sourceHeight: Int,
              edgeMap: LocalBrushEdgeMap?) throws -> LocalAdjustmentMask? {
        try Task.checkCancellation()
        guard instance.strokes.contains(where: { !$0.erasing && $0.isValid }) else { return nil }
        let edgeSignature = instance.strokes.contains(where: { $0.edgeAware }) ? edgeMap?.signature : nil
        let candidate = lookup(instanceID: instance.id, strokes: instance.strokes,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight, edgeSignature: edgeSignature)
        try Task.checkCancellation()
        let settings = [instance.adjustment: instance.maskSettings]
        if let candidate, candidate.count == instance.strokes.count {
            return candidate.mask.applying(settings)
        }

        let start = candidate?.count ?? 0
        guard let mask = try LocalAdjustmentMask(strokes: instance.strokes, sourceWidth: sourceWidth,
            sourceHeight: sourceHeight, edgeMap: edgeMap, reusing: candidate?.mask,
            rasterizingFrom: start) else { return nil }
        try Task.checkCancellation()
        insert(Entry(instanceID: instance.id, strokes: instance.strokes,
            sourceWidth: sourceWidth, sourceHeight: sourceHeight, edgeSignature: edgeSignature,
            mask: mask, bytes: mask.byteCost),
            rasterized: instance.strokes.dropFirst(start).filter(\.isValid).count)
        return mask.applying(settings)
    }

    func statistics() -> Statistics {
        lock.lock()
        defer { lock.unlock() }
        return Statistics(exactHits: exactHits, incrementalHits: incrementalHits, misses: misses,
            rasterizedStrokes: rasterizedStrokes, evictions: evictions, entries: entries.count,
            residentBytes: residentBytes, byteLimit: byteLimit, entryLimit: entryLimit)
    }

    func removeAll() {
        lock.lock()
        entries.removeAll(keepingCapacity: false)
        residentBytes = 0
        exactHits = 0
        incrementalHits = 0
        misses = 0
        rasterizedStrokes = 0
        evictions = 0
        lock.unlock()
    }

    private func lookup(instanceID: UUID, strokes: [LocalBrushStroke], sourceWidth: Int,
                        sourceHeight: Int, edgeSignature: UInt64?) -> (mask: LocalAdjustmentMask, count: Int)? {
        lock.lock()
        defer { lock.unlock() }
        let compatible: (Entry) -> Bool = {
            $0.instanceID == instanceID && $0.sourceWidth == sourceWidth &&
                $0.sourceHeight == sourceHeight && $0.edgeSignature == edgeSignature
        }
        if let index = entries.firstIndex(where: { compatible($0) && $0.strokes == strokes }) {
            let entry = entries.remove(at: index)
            entries.append(entry)
            exactHits += 1
            return (entry.mask, entry.strokes.count)
        }
        let prefix = entries.indices.filter { index in
            let entry = entries[index]
            return compatible(entry) && entry.strokes.count < strokes.count &&
                Array(strokes.prefix(entry.strokes.count)) == entry.strokes
        }.max { entries[$0].strokes.count < entries[$1].strokes.count }
        if let prefix {
            let entry = entries.remove(at: prefix)
            entries.append(entry)
            incrementalHits += 1
            return (entry.mask, entry.strokes.count)
        }
        misses += 1
        return nil
    }

    private func insert(_ entry: Entry, rasterized: Int) {
        lock.lock()
        defer { lock.unlock() }
        rasterizedStrokes += rasterized
        guard entryLimit > 0, entry.bytes <= byteLimit else { return }
        if let duplicate = entries.firstIndex(where: {
            $0.instanceID == entry.instanceID && $0.strokes == entry.strokes &&
                $0.sourceWidth == entry.sourceWidth && $0.sourceHeight == entry.sourceHeight &&
                $0.edgeSignature == entry.edgeSignature
        }) {
            residentBytes -= entries.remove(at: duplicate).bytes
        }
        while !entries.isEmpty &&
                (entries.count >= entryLimit || residentBytes > byteLimit - entry.bytes) {
            residentBytes -= entries.removeFirst().bytes
            evictions += 1
        }
        entries.append(entry)
        residentBytes += entry.bytes
    }
}
