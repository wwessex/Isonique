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

    func testSavedPreviewSurvivesReopeningOfflineAndExportRequiresTheOriginal() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (repository, library, original) = try referencedFixture(in: directory)
        var edited = library
        edited.photos[0].adjustments.crop = PhotoCrop(x: 0, y: 0, width: 0.5, height: 1)
        let saved = try repository.save(edited)
        let photo = saved.photos[0]
        let cacheDirectory = directory.appendingPathComponent("Previews")
        let live = try await saveViewerPreview(photo, repository: repository,
                                              store: OfflineViewerPreviews(directory: cacheDirectory))
        XCTAssertEqual(live.width, 32)
        try FileManager.default.removeItem(at: original)

        let (reopenedRepository, reopened) = try LibraryBackup.openVerified(repository.root)
        let restored = try XCTUnwrap(reopened.photos.first)
        let disk = OfflineViewerPreviews(directory: cacheDirectory)
        let cached = await disk.image(for: restored, in: reopenedRepository.root)
        let preview = try XCTUnwrap(cached)
        XCTAssertEqual(preview.width, live.width)
        XCTAssertEqual(preview.height, live.height)
        XCTAssertEqual(try rgbaPixels(preview), try rgbaPixels(live))
        XCTAssertTrue(reopened.hasSameCatalogueRevision(as: saved))

        for format in [ExportFormat.png, .original] {
            var options = ExportOptions()
            options.format = format
            options.xmpSidecar = true
            let destination = directory.appendingPathComponent("export-\(format).png")
            XCTAssertThrowsError(try Renderer.export(restored, repository: reopenedRepository,
                                                      to: destination, options: options)) { error in
                guard case LibraryError.originalUnavailable = error else {
                    return XCTFail("Expected the missing original error, got \(error)")
                }
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.deletingPathExtension()
                .appendingPathExtension("xmp").path))
        }
    }

    func testOfflinePreviewRequiresCurrentRecipeAndRelinkedSource() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (repository, saved, original) = try referencedFixture(in: directory)
        let photo = saved.photos[0]
        let cache = OfflineViewerPreviews(directory: directory.appendingPathComponent("Previews"))
        _ = try await saveViewerPreview(photo, repository: repository, store: cache)

        var draft = saved
        draft.photos[0].adjustments.exposure = 0.75
        draft = try repository.save(draft)
        let oldRecipe = await cache.image(for: draft.photos[0], in: repository.root)
        XCTAssertNil(oldRecipe)
        let edited = try await saveViewerPreview(draft.photos[0], repository: repository, store: cache)
        let editedPreview = await cache.image(for: draft.photos[0], in: repository.root)
        XCTAssertEqual(try rgbaPixels(XCTUnwrap(editedPreview)), try rgbaPixels(edited))
        let previous = await cache.image(for: photo, in: repository.root)
        XCTAssertNil(previous)

        let moved = directory.appendingPathComponent("Relinked.png")
        try FileManager.default.moveItem(at: original, to: moved)
        try repository.relinkOriginal(photo.id, to: moved, in: &draft)
        let oldLocation = await cache.image(for: draft.photos[0], in: repository.root)
        XCTAssertNil(oldLocation)
        _ = try await saveViewerPreview(draft.photos[0], repository: repository, store: cache)
        try FileManager.default.removeItem(at: moved)
        let relinked = try repository.load().photos[0]
        let offline = await cache.image(for: relinked, in: repository.root)
        XCTAssertEqual(try rgbaPixels(XCTUnwrap(offline)), try rgbaPixels(edited))
    }

    @MainActor
    func testReopenedBrowserLoadsThumbnailsForTheSelectedVersionOnly() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (repository, library, original) = try referencedFixture(in: directory, width: 480)
        var draft = library
        let firstID = draft.photos[0].id
        let alternate = try XCTUnwrap(draft.createVersion(of: firstID, from: .current))
        let unsaved = try XCTUnwrap(draft.createVersion(of: firstID, from: .current))
        draft.photos[1].adjustments.crop = PhotoCrop(x: 0, y: 0, width: 0.5, height: 1)
        draft = try repository.save(draft)
        let previews = directory.appendingPathComponent("Previews")
        let store = OfflineViewerPreviews(directory: previews)
        for photo in draft.photos.prefix(2) { _ = try await saveViewerPreview(photo, repository: repository, store: store) }
        let disconnected = directory.appendingPathComponent("Disconnected.png")
        try FileManager.default.moveItem(at: original, to: disconnected)

        let suite = "IsoniqueOfflineThumbnails.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        let reopened = OfflineViewerPreviews(directory: previews)
        model.openListPhoto(alternate.id)
        XCTAssertTrue(model.viewer)
        let selectedAlternate = try XCTUnwrap(model.selected)
        XCTAssertEqual(selectedAlternate.id, alternate.id)
        let alternateKey = try XCTUnwrap(OfflineViewerPreviews.Key(photo: selectedAlternate, library: repository.root))
        let listImage = await reopened.thumbnail(for: alternateKey, maximum: 96)
        XCTAssertEqual(listImage?.width, 48)
        XCTAssertEqual(listImage?.height, 96)

        model.selectBrowserPhoto(firstID)
        let selectedOriginal = try XCTUnwrap(model.selected)
        XCTAssertEqual(selectedOriginal.id, firstID)
        let originalKey = try XCTUnwrap(OfflineViewerPreviews.Key(photo: selectedOriginal, library: repository.root))
        let filmstripImage = await reopened.thumbnail(for: originalKey, maximum: 220)
        XCTAssertEqual(filmstripImage?.width, 220)
        XCTAssertEqual(filmstripImage?.height, 220)
        let unseenKey = try XCTUnwrap(OfflineViewerPreviews.Key(photo: unsaved, library: repository.root))
        let unseen = await reopened.thumbnail(for: unseenKey, maximum: 220)
        XCTAssertNil(unseen)

        model.edit { $0.adjustments.exposure = 0.5 }
        let edited = try XCTUnwrap(model.selected)
        let editedKey = try XCTUnwrap(OfflineViewerPreviews.Key(photo: edited, library: repository.root))
        let staleAfterEdit = await reopened.thumbnail(for: editedKey, maximum: 220)
        XCTAssertNil(staleAfterEdit)
        let unaffected = await reopened.thumbnail(for: alternateKey, maximum: 96)
        XCTAssertNotNil(unaffected)

        var relinked = try repository.load()
        try repository.relinkOriginal(alternate.id, to: disconnected, in: &relinked)
        let relinkedVariant = try XCTUnwrap(relinked.photos.first { $0.id == alternate.id })
        let relinkedKey = try XCTUnwrap(OfflineViewerPreviews.Key(photo: relinkedVariant, library: repository.root))
        let staleAfterRelink = await reopened.thumbnail(for: relinkedKey, maximum: 96)
        XCTAssertNil(staleAfterRelink)
        _ = try await saveViewerPreview(relinkedVariant, repository: repository, store: reopened)
        try FileManager.default.removeItem(at: disconnected)
        let refreshed = await reopened.thumbnail(for: relinkedKey, maximum: 96)
        XCTAssertEqual(refreshed?.width, 48)
        XCTAssertEqual(refreshed?.height, 96)
    }

    func testPreviewCacheRejectsDifferentOriginalBytesAndPrunesOldVersions() async throws {
        let directory = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let (repository, saved, original) = try referencedFixture(in: directory)
        let photo = saved.photos[0]
        let cache = OfflineViewerPreviews(directory: directory.appendingPathComponent("Previews"), entryLimit: 1)
        try writeFixture(to: original, width: 64, gray: 0.9)
        _ = try await saveViewerPreview(photo, repository: repository, store: cache)
        let wrong = await cache.image(for: photo, in: repository.root)
        XCTAssertNil(wrong)

        try writeFixture(to: original, width: 64, gray: 0.4)
        _ = try await saveViewerPreview(photo, repository: repository, store: cache)
        var draft = saved
        let second = try XCTUnwrap(draft.createVersion(of: photo.id, from: .current))
        _ = try repository.save(draft)
        _ = try await saveViewerPreview(second, repository: repository, store: cache)
        let evicted = await cache.image(for: photo, in: repository.root)
        let remaining = await cache.image(for: second, in: repository.root)
        XCTAssertNil(evicted)
        XCTAssertNotNil(remaining)
    }

    private func referencedFixture(in directory: URL, width: Int = 64) throws -> (LibraryRepository, Library, URL) {
        let repository = try LibraryRepository.createEmpty(at: directory.appendingPathComponent("Library"))
        let original = directory.appendingPathComponent("Referenced.png").resolvingSymlinksInPath()
        try writeFixture(to: original, width: width, gray: 0.4)
        var library = try repository.load()
        var options = ImportOptions()
        options.storage = .referenced
        XCTAssertTrue(try repository.importPhoto(original, projectID: nil, into: &library, options: options))
        return (repository, try repository.save(library), original)
    }

    private func saveViewerPreview(_ photo: Photo, repository: LibraryRepository, store: OfflineViewerPreviews) async throws -> CGImage {
        let original = try repository.availableOriginalURL(photo)
        let frame = try await ViewerRenderCache().frame(url: original, adjustments: photo.adjustments,
                                                       maximum: OfflineViewerPreviews.maximumDimension, revision: 0)
        await store.save(frame.image, of: photo, in: repository.root, original: original, stamp: try XCTUnwrap(frame.sourceStamp))
        return frame.image
    }

    private func rgbaPixels(_ image: CGImage) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                             bytesPerRow: image.width * 4, space: space,
                                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes: try XCTUnwrap(context.data), count: context.bytesPerRow * context.height)
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
