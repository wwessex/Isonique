import XCTest
@testable import IsoniqueCore

final class LocalBrushMaskCacheTests: XCTestCase {
    func testLongSessionRasterizesOnlyAppendedStrokesWithinBudgets() throws {
        let cache = LocalBrushMaskCache(byteLimit: 6 * 1024 * 1024, entryLimit: 4)
        var instance = LocalBrushInstance(name: "Long session", adjustment: .dodge)
        var finalMask: LocalAdjustmentMask?
        for index in 0..<24 {
            instance.strokes.append(stroke(x: 0.05 + Double(index) * 0.035))
            finalMask = try cache.mask(for: instance, sourceWidth: 512, sourceHeight: 512, edgeMap: nil)
        }
        let stats = cache.statistics()
        XCTAssertNotNil(finalMask)
        XCTAssertEqual(stats.misses, 1)
        XCTAssertEqual(stats.incrementalHits, 23)
        XCTAssertEqual(stats.rasterizedStrokes, 24,
                       "Appending 24 strokes must perform 24 stroke rasters, not 1+…+24")
        XCTAssertLessThanOrEqual(stats.entries, stats.entryLimit)
        XCTAssertLessThanOrEqual(stats.residentBytes, stats.byteLimit)

        let clean = try XCTUnwrap(LocalAdjustmentMask(strokes: instance.strokes,
            sourceWidth: 512, sourceHeight: 512))
        let incremental = try XCTUnwrap(finalMask)
        for y in stride(from: 0, to: 512, by: 7) {
            for x in stride(from: 0, to: 512, by: 7) {
                XCTAssertEqual(incremental.coverage(for: .dodge, x: x, y: y,
                    imageWidth: 512, imageHeight: 512),
                    clean.coverage(for: .dodge, x: x, y: y, imageWidth: 512, imageHeight: 512))
            }
        }

        instance.strokes[0] = stroke(x: 0.9)
        _ = try cache.mask(for: instance, sourceWidth: 512, sourceHeight: 512, edgeMap: nil)
        let invalidated = cache.statistics()
        XCTAssertEqual(invalidated.misses, 2, "Editing an earlier stroke must invalidate every cached prefix")
        XCTAssertEqual(invalidated.rasterizedStrokes, 48)
    }

    func testLargeSourceMaskAndCacheStayWithinMemoryBudget() throws {
        let budget = 16 * 1024 * 1024
        let cache = LocalBrushMaskCache(byteLimit: budget, entryLimit: 2)
        let instance = LocalBrushInstance(name: "Large source", adjustment: .dodge,
            strokes: [stroke(x: 0.5)])
        let mask = try XCTUnwrap(cache.mask(for: instance, sourceWidth: 12_000,
                                            sourceHeight: 8_000, edgeMap: nil))
        XCTAssertEqual(mask.width, 2048)
        XCTAssertEqual(mask.height, 1365)
        XCTAssertLessThanOrEqual(cache.statistics().residentBytes, budget)
        _ = try cache.mask(for: instance, sourceWidth: 12_000, sourceHeight: 8_000, edgeMap: nil)
        XCTAssertEqual(cache.statistics().exactHits, 1)
        XCTAssertEqual(cache.statistics().rasterizedStrokes, 1)
    }

    func testEdgeFingerprintAndGeometryInvalidateCachedMask() throws {
        let cache = LocalBrushMaskCache(byteLimit: 4 * 1024 * 1024, entryLimit: 4)
        let edgeStroke = LocalBrushStroke(adjustment: .dodge, radius: 0.04, softness: 0.4,
            strength: 0.8, edgeAware: true, points: [BrushPoint(x: 0.5, y: 0.5)])
        let instance = LocalBrushInstance(name: "Protected", adjustment: .dodge,
                                          strokes: [edgeStroke])
        let dark = edgeMap(gray: 30)
        let light = edgeMap(gray: 220)
        _ = try cache.mask(for: instance, sourceWidth: 128, sourceHeight: 96, edgeMap: dark)
        _ = try cache.mask(for: instance, sourceWidth: 128, sourceHeight: 96, edgeMap: dark)
        XCTAssertEqual(cache.statistics().exactHits, 1)
        _ = try cache.mask(for: instance, sourceWidth: 128, sourceHeight: 96, edgeMap: light)
        _ = try cache.mask(for: instance, sourceWidth: 256, sourceHeight: 192, edgeMap: light)
        XCTAssertEqual(cache.statistics().misses, 3)
        XCTAssertEqual(cache.statistics().rasterizedStrokes, 3)
    }

    func testCancellationNeverReturnsOrPublishesCachedWork() async throws {
        let cache = LocalBrushMaskCache(byteLimit: 1024 * 1024, entryLimit: 2)
        let instance = LocalBrushInstance(name: "Cancelled", adjustment: .dodge,
                                          strokes: [stroke(x: 0.5)])
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try cache.mask(for: instance, sourceWidth: 512, sourceHeight: 512, edgeMap: nil)
        }
        do {
            _ = try await task.value
            XCTFail("A cancelled mask request returned a raster")
        } catch is CancellationError {}
        XCTAssertEqual(cache.statistics().entries, 0)
        XCTAssertEqual(cache.statistics().rasterizedStrokes, 0)
    }

    private func stroke(x: Double) -> LocalBrushStroke {
        LocalBrushStroke(adjustment: .dodge, radius: 0.012, softness: 0.35,
            strength: 0.7, points: [BrushPoint(x: x, y: 0.5,
                radiusScale: 0.8, strengthScale: 0.65)])
    }

    private func edgeMap(gray: UInt8) -> LocalBrushEdgeMap {
        let width = 128, height = 96
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            pixels[offset] = gray
            pixels[offset + 1] = gray
            pixels[offset + 2] = gray
        }
        return pixels.withUnsafeBufferPointer {
            LocalBrushEdgeMap(pixels: $0.baseAddress!, width: width, height: height)
        }
    }
}
