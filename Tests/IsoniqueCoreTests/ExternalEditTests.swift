import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import IsoniqueCore

final class ExternalEditTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueExternalEditTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporary)
    }

    func testReturnedTIFFBecomesPersistentDerivativeWithoutChangingSource() throws {
        let (repository, original, sourceBytes) = try fixture()
        let handoff = try repository.beginExternalEdit(original)
        let returned = try replaceReturn(handoff, repository: repository, photo: original, exposure: 1.0)

        let result = try repository.finishExternalEdit(handoff, in: try repository.load())
        XCTAssertEqual(result.library.photos.count, 2)
        XCTAssertEqual(result.photo.versionName, "Source — External Edit")
        XCTAssertNil(result.photo.sharedOriginalID)
        XCTAssertNil(result.photo.referencedPath)
        XCTAssertEqual(result.photo.projectID, original.projectID)
        XCTAssertEqual(result.photo.albumIDs, original.albumIDs)
        XCTAssertEqual(result.photo.caption, original.caption)
        XCTAssertEqual(result.photo.keywords, original.keywords)
        XCTAssertEqual(result.photo.adjustments, Adjustments())
        XCTAssertEqual(try Data(contentsOf: repository.availableOriginalURL(original)), sourceBytes)
        let derivativeURL = try repository.availableOriginalURL(result.photo)
        XCTAssertEqual(try Data(contentsOf: derivativeURL), returned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: handoff.fileURL.path))

        let preview = try Renderer.render(derivativeURL, adjustments: result.photo.adjustments)
        let exportedURL = temporary.appendingPathComponent("External-return-preview.png")
        var exportOptions = ExportOptions()
        exportOptions.format = .png
        try Renderer.export(result.photo, repository: repository, to: exportedURL, options: exportOptions)
        let exportSource = try XCTUnwrap(CGImageSourceCreateWithURL(exportedURL as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(exportSource, 0, nil))
        XCTAssertEqual(try rgba(preview), try rgba(exported))

        let reopened = try repository.reloadCatalogue()
        let persistent = try XCTUnwrap(reopened.photos.first(where: { $0.id == result.photo.id }))
        XCTAssertEqual(persistent, result.photo)
        XCTAssertEqual(try Data(contentsOf: repository.availableOriginalURL(persistent)), returned)
    }

    func testCancellationRemovesOnlyHandoffAndLeavesLibraryUntouched() throws {
        let (repository, original, sourceBytes) = try fixture()
        let handoff = try repository.beginExternalEdit(original)
        let directory = handoff.fileURL.deletingLastPathComponent()
        XCTAssertTrue(FileManager.default.fileExists(atPath: handoff.fileURL.path))

        try repository.cancelExternalEdit(handoff)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(try repository.load().photos, [original])
        XCTAssertEqual(try Data(contentsOf: repository.availableOriginalURL(original)), sourceBytes)
    }

    func testMissingAndUnchangedReturnsAreRejectedWithoutCatalogueChanges() throws {
        let (repository, original, _) = try fixture()
        let missing = try repository.beginExternalEdit(original)
        try FileManager.default.removeItem(at: missing.fileURL)
        XCTAssertThrowsError(try repository.finishExternalEdit(missing, in: repository.load())) { error in
            XCTAssertEqual(error as? ExternalEditError, .returnMissing)
        }
        XCTAssertEqual(try repository.load().photos.count, 1)
        try repository.cancelExternalEdit(missing)

        let unchanged = try repository.beginExternalEdit(original)
        XCTAssertThrowsError(try repository.finishExternalEdit(unchanged, in: repository.load())) { error in
            XCTAssertEqual(error as? ExternalEditError, .returnUnchanged)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: unchanged.fileURL.path))
        XCTAssertEqual(try repository.load().photos.count, 1)
        try repository.cancelExternalEdit(unchanged)
    }

    func testInvalidReturnAndStaleCatalogueRollBackManagedCopy() throws {
        let (repository, original, _) = try fixture()
        let invalid = try repository.beginExternalEdit(original)
        try Data("not a TIFF".utf8).write(to: invalid.fileURL)
        XCTAssertThrowsError(try repository.finishExternalEdit(invalid, in: repository.load())) { error in
            XCTAssertEqual(error as? ExternalEditError, .returnIsNotTIFF)
        }
        try repository.cancelExternalEdit(invalid)

        let stale = try repository.load()
        let handoff = try repository.beginExternalEdit(original)
        _ = try replaceReturn(handoff, repository: repository, photo: original, exposure: -0.8)
        let other = try LibraryRepository(root: repository.root)
        var newer = try other.load()
        newer.projects.append(Collection(name: "Newer work"))
        _ = try other.save(newer)
        let originals = repository.root.appendingPathComponent("Originals")
        let before = try FileManager.default.contentsOfDirectory(atPath: originals.path)

        XCTAssertThrowsError(try repository.finishExternalEdit(handoff, in: stale)) { error in
            guard case LibraryError.staleCatalogue = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: originals.path), before)
        XCTAssertEqual(try repository.load().photos.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: handoff.fileURL.path))
        try repository.cancelExternalEdit(handoff)
    }

    func testReturnAlreadyImportedElsewhereIsRejectedAsDuplicate() throws {
        let (repository, original, _) = try fixture()
        let handoff = try repository.beginExternalEdit(original)
        _ = try replaceReturn(handoff, repository: repository, photo: original, exposure: 0.9)
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(handoff.fileURL, projectID: nil, into: &library))

        XCTAssertThrowsError(try repository.finishExternalEdit(handoff, in: library)) { error in
            XCTAssertEqual(error as? ExternalEditError, .duplicateReturn)
        }
        XCTAssertEqual(try repository.load().photos.count, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: handoff.fileURL.path))
        try repository.cancelExternalEdit(handoff)
    }

    private func fixture() throws -> (LibraryRepository, Photo, Data) {
        let source = try makeImage(temporary.appendingPathComponent("Source.png"), red: 0.2)
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        let project = Collection(name: "Project")
        let album = Collection(name: "Album")
        library.projects.append(project)
        library.albums.append(album)
        XCTAssertTrue(try repository.importPhoto(source, projectID: project.id, into: &library, albumID: album.id))
        var photo = try XCTUnwrap(library.photos.first)
        photo.caption = "External round trip"
        photo.keywords = "studio, portrait"
        photo.rating = 4
        photo.adjustments.exposure = 0.35
        library.photos[0] = photo
        library = try repository.save(library)
        photo = try XCTUnwrap(library.photos.first)
        return (repository, photo, try Data(contentsOf: repository.availableOriginalURL(photo)))
    }

    @discardableResult
    private func replaceReturn(_ handoff: ExternalEditHandoff, repository: LibraryRepository,
                               photo: Photo, exposure: Double) throws -> Data {
        try FileManager.default.removeItem(at: handoff.fileURL)
        var edited = photo
        edited.adjustments.exposure = exposure
        var options = ExportOptions()
        options.format = .tiff
        options.tiffCompression = .zip
        try Renderer.export(edited, repository: repository, to: handoff.fileURL, options: options)
        return try Data(contentsOf: handoff.fileURL)
    }

    @discardableResult
    private func makeImage(_ url: URL, red: CGFloat) throws -> URL {
        let space = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(CGContext(data: nil, width: 32, height: 24, bitsPerComponent: 8,
                                              bytesPerRow: 128, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.65, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                  CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
}
