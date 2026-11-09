import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import IsoniqueCore
@testable import Isonique

final class ThumbnailCacheTests: XCTestCase {
    func testReuseAndInvalidationForRecipeSizeRevisionAndOriginal() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Original.png")
        try writeFixture(url, side: 40, gray: 0.25)
        let id = UUID()
        let cache = ThumbnailCache()
        func load(maximum: Int = 32, revision: Int = 0, edits: Adjustments = Adjustments()) async throws -> CGImage {
            try await cache.image(for: .init(photoID: id, url: url, adjustments: edits, maximum: maximum, revision: revision))
        }
        let first = try await load()
        let hit = try await load()
        XCTAssertTrue(first === hit)
        let smaller = try await load(maximum: 16)
        XCTAssertEqual(smaller.width, 16)
        let refreshed = try await load(revision: 1)
        XCTAssertFalse(first === refreshed)
        var edits = Adjustments()
        edits.exposure = 1
        let edited = try await load(edits: edits)
        XCTAssertFalse(refreshed === edited)
        let matchingEdited = try await load(edits: edits)
        XCTAssertTrue(matchingEdited === edited)
        try writeFixture(url, side: 24, gray: 0.8)
        let replaced = try await load(edits: edits)
        XCTAssertEqual(replaced.width, 24)
        XCTAssertFalse(replaced === edited)
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await load(edits: edits)
            XCTFail("Deleted original returned a cached thumbnail")
        } catch is LibraryError {}
    }

    func testLRUEvictsUnderByteBudget() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Versions.png")
        try writeFixture(url, side: 16, gray: 0.4)
        let cache = ThumbnailCache(byteLimit: 2 * 64 * 16)
        let ids = [UUID(), UUID(), UUID()]
        func load(_ index: Int) async throws -> CGImage {
            try await cache.image(for: .init(photoID: ids[index], url: url, adjustments: Adjustments(),
                                             maximum: 16, revision: 0))
        }
        let first = try await load(0)
        let second = try await load(1)
        _ = try await load(0)
        _ = try await load(2)
        let hit = try await load(0)
        let miss = try await load(1)
        XCTAssertTrue(first === hit)
        XCTAssertFalse(second === miss)
    }

    func testSharedDecodeAndQueuedCancellation() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Shared.png")
        try writeFixture(url, side: 16, gray: 0.4)
        let started = expectation(description: "first thumbnail is decoding")
        let gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let counter = RenderCounter()
        let cache = ThumbnailCache(workerLimit: 1) { request in
            if counter.enter() == 1 {
                started.fulfill()
                _ = gate.wait(timeout: .now() + 5)
            }
            defer { counter.leave() }
            return try Renderer.thumbnail(request.url, adjustments: request.adjustments, maxDimension: request.maximum)
        }
        let request = ThumbnailCache.Request(photoID: UUID(), url: url, adjustments: Adjustments(), maximum: 16, revision: 0)
        let first = Task { try await cache.image(for: request) }
        await fulfillment(of: [started], timeout: 5)
        let joined = Task { try await cache.image(for: request) }
        let other = ThumbnailCache.Request(photoID: UUID(), url: url, adjustments: Adjustments(), maximum: 16, revision: 0)
        let cancelled = Task { try await cache.image(for: other) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled request returned a thumbnail")
        } catch is CancellationError {}
        gate.signal()
        let a = try await first.value
        let b = try await joined.value
        XCTAssertTrue(a === b)
        XCTAssertEqual(counter.calls, 1)
    }

    func testWorkerLimitAndRejectsOriginalChangedMidDecode() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = (0..<5).map { folder.appendingPathComponent("\($0).png") }
        for url in urls { try writeFixture(url, side: 16, gray: 0.4) }
        let firstWorkers = expectation(description: "two workers reached the decode gate")
        firstWorkers.expectedFulfillmentCount = 2
        let changedStarted = expectation(description: "first worker started on the source to be replaced")
        let gate = DispatchSemaphore(value: 0)
        let counter = RenderCounter()
        let cache = ThumbnailCache(workerLimit: 2) { request in
            let order = counter.enter()
            if order == 1 { changedStarted.fulfill() }
            defer { counter.leave() }
            let image = try Renderer.thumbnail(request.url, adjustments: request.adjustments, maxDimension: request.maximum)
            if order <= 2 { firstWorkers.fulfill() }
            _ = gate.wait(timeout: .now() + 5)
            return image
        }
        let changed = ThumbnailCache.Request(photoID: UUID(), url: urls[0], adjustments: Adjustments(), maximum: 16, revision: 0)
        let work = Task { try await cache.image(for: changed) }
        // Ensure the known source is among the two gated decodes.
        await fulfillment(of: [changedStarted], timeout: 5)
        let remaining = urls.dropFirst().map { url in
            Task { try await cache.image(for: .init(photoID: UUID(), url: url, adjustments: Adjustments(), maximum: 16, revision: 0)) }
        }
        defer { for _ in urls { gate.signal() } }
        await fulfillment(of: [firstWorkers], timeout: 5)
        try writeFixture(urls[0], side: 24, gray: 0.8)
        for _ in urls { gate.signal() }
        do {
            _ = try await work.value
            XCTFail("Thumbnail from a changed source was delivered")
        } catch is LibraryError {}
        for task in remaining { _ = try await task.value }
        XCTAssertEqual(counter.peak, 2)
        XCTAssertEqual(counter.calls, 5)
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueThumbnails-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func writeFixture(_ url: URL, side: Int, gray: Double) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                                             bytesPerRow: side * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let data = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        try (data as Data).write(to: url, options: .atomic)
    }
}

private final class RenderCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var started = 0
    private var active = 0
    private var high = 0

    var calls: Int { lock.withLock { started } }
    var peak: Int { lock.withLock { high } }

    func enter() -> Int {
        lock.withLock {
            started += 1
            active += 1
            high = max(high, active)
            return started
        }
    }

    func leave() { lock.withLock { active -= 1 } }
}
