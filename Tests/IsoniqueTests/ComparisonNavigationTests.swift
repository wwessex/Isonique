import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import IsoniqueCore
@testable import Isonique

final class ComparisonNavigationTests: XCTestCase {
    func testSynchronizedAndIndependentNavigation() {
        var pair = ComparisonNavigationPair()
        var reference = ComparisonNavigation(scale: 2)
        reference.moveCenter(to: CGPoint(x: 0.7, y: 0.35))
        pair.update(reference, for: .reference)
        XCTAssertEqual(pair.reference, reference)
        XCTAssertEqual(pair.selected, reference)

        pair.setSynchronized(false)
        var selected = ComparisonNavigation(scale: 0.5)
        selected.moveCenter(to: CGPoint(x: 0.25, y: 0.8))
        pair.update(selected, for: .selected)
        XCTAssertEqual(pair.reference, reference)
        XCTAssertEqual(pair.selected, selected)

        pair.setSynchronized(true)
        XCTAssertEqual(pair.selected, reference,
                       "Re-locking navigation makes the reference pane authoritative")
        reference.toggleActualPixels()
        pair.update(reference, for: .selected)
        XCTAssertNil(pair.reference.scale)
        XCTAssertEqual(pair.reference.center, CGPoint(x: 0.5, y: 0.5))
        XCTAssertEqual(pair.selected, pair.reference)
    }

    func testNormalizedPanMatchesDifferentAspectRatiosAndClampsEdges() {
        let center = CGPoint(x: 0.65, y: 0.4)
        let visible = CGSize(width: 400, height: 300)
        for image in [CGSize(width: 2400, height: 900), CGSize(width: 900, height: 2400)] {
            let origin = ComparisonViewportGeometry.origin(center: center,
                visibleSize: visible, imageSize: image)
            XCTAssertEqual(ComparisonViewportGeometry.normalizedCenter(origin: origin,
                visibleSize: visible, imageSize: image).x, center.x, accuracy: 0.000_001)
            XCTAssertEqual(ComparisonViewportGeometry.normalizedCenter(origin: origin,
                visibleSize: visible, imageSize: image).y, center.y, accuracy: 0.000_001)
        }
        let clamped = ComparisonViewportGeometry.origin(center: CGPoint(x: -2, y: 4),
            visibleSize: visible, imageSize: CGSize(width: 1000, height: 800))
        XCTAssertEqual(clamped, CGPoint(x: 0, y: 500))
        var navigation = ComparisonNavigation(scale: 1)
        navigation.moveCenter(to: CGPoint(x: -.infinity, y: .nan))
        XCTAssertEqual(navigation.center, CGPoint(x: 0.5, y: 0.5))
        navigation.moveCenter(to: CGPoint(x: -1, y: 2))
        XCTAssertEqual(navigation.center, CGPoint(x: 0, y: 1))
    }

    func testSmallTrackpadDeltasAccumulateFromFitAcrossTheGesture() {
        var session = ComparisonMagnificationSession()
        let first = session.sample(current: nil, delta: 0.01, began: true, ended: false)
        XCTAssertNil(first.base)
        XCTAssertEqual(first.factor, 1.01, accuracy: 0.000_001)
        let second = session.sample(current: nil, delta: 0.01, began: false, ended: false)
        XCTAssertEqual(second.factor, 1.0201, accuracy: 0.000_001)
        let third = session.sample(current: nil, delta: 0.01, began: false, ended: false)
        XCTAssertEqual(third.factor, 1.030301, accuracy: 0.000_001)
        XCTAssertEqual(try XCTUnwrap(ViewerZoom.magnified(from: third.base, by: third.factor)),
                       third.factor, accuracy: 0.000_001)
        _ = session.sample(current: nil, delta: 0, began: false, ended: true)
        XCTAssertFalse(session.active)
        XCTAssertEqual(session.factor, 1)
    }

    @MainActor
    func testScrollViewportAppliesAndReportsNormalizedPanWithoutFeedback() throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueComparisonViewport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        _ = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let model = Workspace(libraryRoot: folder.appendingPathComponent("Library"))
        let context = try XCTUnwrap(CGContext(data: nil, width: 1000, height: 500,
            bitsPerComponent: 8, bytesPerRow: 4000,
            space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue))
        let image = try ViewerImage(try XCTUnwrap(context.makeImage()), proofProfile: nil)
        let scroll = ComparisonScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
        scroll.update(image: image, model: model, label: "Fixture")
        scroll.layoutSubtreeIfNeeded()
        var callbacks: [ComparisonNavigation] = []
        scroll.navigationChanged = { callbacks.append($0) }
        let applied = ComparisonNavigation(scale: 1, center: CGPoint(x: 0.7, y: 0.5))
        scroll.apply(applied)
        XCTAssertEqual(scroll.magnification, 1, accuracy: 0.000_1)
        XCTAssertTrue(callbacks.isEmpty, "Applying shared state must not feed back as a user pan")

        let userOrigin = CGPoint(x: 250, y: 80)
        scroll.contentView.scroll(to: userOrigin)
        scroll.reflectScrolledClipView(scroll.contentView)
        let reported = try XCTUnwrap(callbacks.last)
        let expected = ComparisonViewportGeometry.normalizedCenter(origin: scroll.contentView.bounds.origin,
            visibleSize: scroll.contentView.bounds.size, imageSize: image.size)
        XCTAssertEqual(reported.center.x, expected.x, accuracy: 0.000_001)
        XCTAssertEqual(reported.center.y, expected.y, accuracy: 0.000_001)
        XCTAssertEqual(reported.scale, 1)
    }

    @MainActor
    func testFullResolutionTransitionCancellationComparisonChangeAndExportIsolation() async throws {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueComparisonNavigation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let wideSource = folder.appendingPathComponent("Wide.png")
        let tallSource = folder.appendingPathComponent("Tall.png")
        try writeFixture(wideSource, width: 2200, height: 800, color: (70, 110, 180))
        try writeFixture(tallSource, width: 800, height: 2200, color: (180, 95, 55))
        let wideDigest = try LibraryRepository.digest(wideSource)
        let tallDigest = try LibraryRepository.digest(tallSource)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(wideSource, projectID: nil, into: &library))
        XCTAssertTrue(try repository.importPhoto(tallSource, projectID: nil, into: &library))
        library.photos[0].adjustments.exposure = 0.35
        library = try repository.save(library)
        let wide = library.photos[0], tall = library.photos[1]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let catalogueBefore = try encoder.encode(library)
        let cache = ViewerRenderCache()

        let fit = ComparisonRenderRequest(repository: repository, photo: wide,
            navigation: ComparisonNavigation(), revision: 0, profile: nil)
        XCTAssertEqual(fit.maximum, 1800)
        let fitImage = try await ComparisonImageLoader.load(wide, request: fit,
            repository: repository, cache: cache)
        XCTAssertEqual(max(fitImage.rendered.width, fitImage.rendered.height), 1800)

        let actual = ComparisonRenderRequest(repository: repository, photo: wide,
            navigation: ComparisonNavigation(scale: 1), revision: 0, profile: nil)
        XCTAssertNil(actual.maximum)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ComparisonImageLoader.load(wide, request: actual,
                repository: repository, cache: cache)
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled full-resolution comparison returned an image")
        } catch is CancellationError {}

        let full = try await ComparisonImageLoader.load(wide, request: actual,
            repository: repository, cache: cache)
        XCTAssertEqual(full.rendered.width, 2200)
        XCTAssertEqual(full.rendered.height, 800)
        let changed = ComparisonRenderRequest(repository: repository, photo: tall,
            navigation: ComparisonNavigation(scale: 1), revision: 0, profile: nil)
        XCTAssertNotEqual(changed, actual)
        let tallImage = try await ComparisonImageLoader.load(tall, request: changed,
            repository: repository, cache: cache)
        XCTAssertEqual(tallImage.rendered.width, 800)
        XCTAssertEqual(tallImage.rendered.height, 2200)

        var options = ExportOptions()
        options.format = .png
        let firstExport = folder.appendingPathComponent("Before-navigation.png")
        let secondExport = folder.appendingPathComponent("After-navigation.png")
        try Renderer.export(wide, repository: repository, to: firstExport, options: options)
        XCTAssertEqual(try pixels(full.rendered), try pixels(decode(firstExport)))
        var pair = ComparisonNavigationPair()
        pair.update(ComparisonNavigation(scale: 4, center: CGPoint(x: 0.8, y: 0.2)),
                    for: .reference)
        pair.setSynchronized(false)
        pair.update(ComparisonNavigation(scale: 0.5, center: CGPoint(x: 0.2, y: 0.8)),
                    for: .selected)
        try Renderer.export(wide, repository: repository, to: secondExport, options: options)
        XCTAssertEqual(try LibraryRepository.digest(firstExport),
                       try LibraryRepository.digest(secondExport))
        XCTAssertEqual(try encoder.encode(repository.load()), catalogueBefore)
        XCTAssertEqual(try LibraryRepository.digest(wideSource), wideDigest)
        XCTAssertEqual(try LibraryRepository.digest(tallSource), tallDigest)
        XCTAssertEqual(try LibraryRepository.digest(try repository.availableOriginalURL(wide)), wideDigest)
        XCTAssertEqual(try LibraryRepository.digest(try repository.availableOriginalURL(tall)), tallDigest)
    }

    private func writeFixture(_ url: URL, width: Int, height: Int,
                              color: (UInt8, UInt8, UInt8)) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(red: CGFloat(color.0) / 255, green: CGFloat(color.1) / 255,
                             blue: CGFloat(color.2) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    private func decode(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixels(_ image: CGImage) throws -> [UInt8] {
        var result = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: &result, width: image.width,
            height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return result
    }
}
