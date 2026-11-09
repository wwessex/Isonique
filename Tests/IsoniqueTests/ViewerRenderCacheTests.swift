import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import IsoniqueCore
@testable import Isonique

final class ViewerRenderCacheTests: XCTestCase {
    func testReuseSeparatesResolutionEditsAndOriginalRevision() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Source.png")
        try writeFixture(to: url, width: 64, gray: 0.4)
        let cache = ViewerRenderCache()
        let neutral = Adjustments()
        let first = try await cache.frame(url: url, adjustments: neutral, maximum: nil, revision: 0)
        let fit = try await cache.frame(url: url, adjustments: neutral, maximum: 32, revision: 0)
        XCTAssertEqual(fit.image.width, 32)
        XCTAssertFalse(fit.image === first.image)
        var edited = neutral
        edited.exposure = 0.8
        let modified = try await cache.frame(url: url, adjustments: edited, maximum: nil, revision: 0)
        XCTAssertFalse(modified.image === first.image)
        let hit = try await cache.frame(url: url, adjustments: neutral, maximum: nil, revision: 0)
        XCTAssertTrue(hit.image === first.image)
        XCTAssertEqual(hit.geometry, first.geometry)
        let refreshed = try await cache.frame(url: url, adjustments: neutral, maximum: nil, revision: 1)
        XCTAssertFalse(refreshed.image === first.image)
    }

    func testReplacementAndDeletionNeverUseOldFrame() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Referenced.png")
        try writeFixture(to: url, width: 16, gray: 0.2)
        let cache = ViewerRenderCache()
        let first = try await cache.frame(url: url, adjustments: Adjustments(), maximum: nil, revision: 0)
        try writeFixture(to: url, width: 24, gray: 0.8)
        let replacement = try await cache.frame(url: url, adjustments: Adjustments(), maximum: nil, revision: 0)
        XCTAssertFalse(replacement.image === first.image)
        XCTAssertEqual(replacement.image.width, 24)
        try FileManager.default.removeItem(at: url)
        do {
            _ = try await cache.frame(url: url, adjustments: Adjustments(), maximum: nil, revision: 0)
            XCTFail("Removed original returned a cached frame")
        } catch is LibraryError {}
    }

    func testByteBudgetEvictsLeastRecentlyUsedAndChargesCropBacking() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let a = directory.appendingPathComponent("A.png")
        let b = directory.appendingPathComponent("B.png")
        let c = directory.appendingPathComponent("C.png")
        let large = directory.appendingPathComponent("Large.png")
        for url in [a, b, c] { try writeFixture(to: url, width: 16, gray: 0.4) }
        try writeFixture(to: large, width: 64, gray: 0.6)
        let cache = ViewerRenderCache(byteLimit: 2 * 64 * 16)
        func load(_ url: URL, adjustments: Adjustments = Adjustments()) async throws -> CGImage {
            try await cache.frame(url: url, adjustments: adjustments, maximum: nil, revision: 0).image
        }
        let firstA = try await load(a)
        let firstB = try await load(b)
        _ = try await load(a)
        _ = try await load(c)
        let hitA = try await load(a)
        XCTAssertTrue(hitA === firstA)
        let secondB = try await load(b)
        XCTAssertFalse(secondB === firstB)
        var crop = Adjustments()
        crop.crop = PhotoCrop(x: 0, y: 0, width: 0.1, height: 0.1)
        let cropped = try await load(large, adjustments: crop)
        let secondCrop = try await load(large, adjustments: crop)
        XCTAssertLessThan(cropped.width, 16)
        XCTAssertFalse(cropped === secondCrop)
        let finalA = try await load(a)
        XCTAssertTrue(finalA === firstA)
    }

    func testCancelledRequestDoesNotDeliverCachedFrame() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Source.png")
        try writeFixture(to: url, width: 16, gray: 0.3)
        let cache = ViewerRenderCache()
        _ = try await cache.frame(url: url, adjustments: Adjustments(), maximum: nil, revision: 0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await cache.frame(url: url, adjustments: Adjustments(), maximum: nil, revision: 0)
        }
        do {
            _ = try await task.value
            XCTFail("Cancelled request returned a cached frame")
        } catch is CancellationError {}
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueCache-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func writeFixture(to url: URL, width: Int, gray: Double) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: width, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: width))
        let data = NSMutableData()
        let writer = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        try (data as Data).write(to: url, options: .atomic)
    }
}
