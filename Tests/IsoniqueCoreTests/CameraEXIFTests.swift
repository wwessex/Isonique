import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testCameraEXIFReadsRotatedJPEGAndReportsMissingAndOfflineOriginals() throws {
        let jpeg = try exifJPEG("Portrait.jpg", exif: [
            kCGImagePropertyExifExposureTime as String: 1.0 / 125,
            kCGImagePropertyExifFNumber as String: 2.8,
            kCGImagePropertyExifISOSpeedRatings as String: [640],
            kCGImagePropertyExifFocalLength as String: 35.5,
            kCGImagePropertyExifLensModel as String: "Test 35 mm"
        ], orientation: 6)
        let sparse = try exifJPEG("Sparse.jpg", exif: [kCGImagePropertyExifFNumber as String: 8])
        let empty = try exifJPEG("Empty.jpg", exif: [:])
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        var options = ImportOptions()
        options.storage = .referenced
        for original in [jpeg, sparse, empty] {
            XCTAssertTrue(try repository.importPhoto(original, projectID: nil, into: &library, options: options))
        }
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let catalogueBefore = try Data(contentsOf: catalogue)
        let originalHash = try LibraryRepository.digest(jpeg)
        let full = try repository.cameraEXIF(for: library.photos[0])
        XCTAssertEqual(library.photos[0].cameraEXIF, full)
        XCTAssertEqual(try XCTUnwrap(full.exposureSeconds), 1.0 / 125, accuracy: 0.000001)
        XCTAssertEqual(try XCTUnwrap(full.fNumber), 2.8, accuracy: 0.001)
        XCTAssertEqual(full.iso, 640)
        XCTAssertEqual(full.focalLengthMM, 35.5)
        XCTAssertEqual(full.lens, "Test 35 mm")
        let originalSource = try XCTUnwrap(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(originalSource, 0, nil) as? [String: Any])
        XCTAssertEqual(properties[kCGImagePropertyOrientation as String] as? Int, 6)

        let partial = try repository.cameraEXIF(for: library.photos[1])
        XCTAssertEqual(partial.fNumber, 8)
        XCTAssertNil(partial.exposureSeconds)
        XCTAssertNil(partial.iso)
        XCTAssertNil(partial.focalLengthMM)
        XCTAssertNil(partial.lens)
        XCTAssertTrue(try repository.cameraEXIF(for: library.photos[2]).isEmpty)

        let offline = temporary.appendingPathComponent("Offline.jpg")
        try FileManager.default.moveItem(at: jpeg, to: offline)
        XCTAssertThrowsError(try repository.cameraEXIF(for: library.photos[0])) { error in
            guard case LibraryError.originalUnavailable(_) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        try Data("unreadable".utf8).write(to: jpeg)
        XCTAssertThrowsError(try repository.cameraEXIF(for: library.photos[0])) { error in
            guard case LibraryError.unsupportedImage(_) = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        try FileManager.default.removeItem(at: jpeg)
        try FileManager.default.moveItem(at: offline, to: jpeg)
        XCTAssertEqual(try repository.cameraEXIF(for: library.photos[0]), full)
        XCTAssertEqual(try LibraryRepository.digest(jpeg), originalHash)
        XCTAssertEqual(try Data(contentsOf: catalogue), catalogueBefore)
    }

    func testCameraEXIFUsesValidAPEXAndAuxiliaryValues() throws {
        let metadata = CameraEXIF(properties: [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifExposureTime as String: 0,
                kCGImagePropertyExifShutterSpeedValue as String: -1,
                kCGImagePropertyExifFNumber as String: Double.nan,
                kCGImagePropertyExifApertureValue as String: 4,
                kCGImagePropertyExifISOSpeedRatings as String: [NSNumber(value: true), -2, 12.5],
                kCGImagePropertyExifISOSpeed as String: 320,
                kCGImagePropertyExifFocalLength as String: Double.infinity,
                kCGImagePropertyExifLensModel as String: " "
            ],
            kCGImagePropertyExifAuxDictionary as String: [kCGImagePropertyExifAuxLensModel as String: "  Aux Lens  "]
        ])
        XCTAssertEqual(metadata.exposureSeconds, 2)
        XCTAssertEqual(metadata.fNumber, 4)
        XCTAssertEqual(metadata.iso, 320)
        XCTAssertNil(metadata.focalLengthMM)
        XCTAssertEqual(metadata.lens, "Aux Lens")
    }

    func testCatalogueEXIFBackfillsOlderPhotosAndSearchesOfflineAfterReopening() throws {
        let source = try exifJPEG("Online.jpg", exif: [
            kCGImagePropertyExifExposureTime as String: 1.0 / 125,
            kCGImagePropertyExifFNumber as String: 2.8,
            kCGImagePropertyExifISOSpeedRatings as String: [400],
            kCGImagePropertyExifFocalLength as String: 35.5,
            kCGImagePropertyExifLensModel as String: "Test 35 mm"
        ])
        let offline = try exifJPEG("Offline.jpg", exif: [kCGImagePropertyExifFNumber as String: 8])
        let empty = try exifJPEG("Empty.jpg", exif: [:])
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var draft = try repo.load()
        var options = ImportOptions()
        options.storage = .referenced
        for original in [source, offline, empty] {
            XCTAssertTrue(try repo.importPhoto(original, projectID: nil, into: &draft, options: options))
        }
        for index in draft.photos.indices { draft.photos[index].cameraEXIF = nil }
        draft.version = 2
        let id = draft.photos[0].id
        let sibling = try XCTUnwrap(draft.createVersion(of: id, from: .current))
        var history = EditHistory()
        history.record(draft.photos[0])
        draft.photos[0].caption = "Edited before backfill"
        draft.history = history
        draft = try repo.save(draft)
        try FileManager.default.removeItem(at: offline)
        let offlineID = draft.photos[1].id
        let ids = Set(draft.photos.map(\.id))
        let indexed = try repo.catalogueEXIF(for: ids, in: &draft)
        XCTAssertEqual(indexed.indexed, 3)
        XCTAssertEqual(indexed.withValues, 2)
        XCTAssertEqual(indexed.issues.count, 1)
        XCTAssertTrue(indexed.issues.first?.contains("Offline.jpg") == true)
        XCTAssertNil(draft.photos.first { $0.id == offlineID }?.cameraEXIF)
        XCTAssertEqual(draft.photos.first { $0.id == sibling.id }?.cameraEXIF, draft.photos[0].cameraEXIF)
        XCTAssertEqual(draft.photos[2].cameraEXIF?.isEmpty, true)
        XCTAssertEqual(try repo.catalogueEXIF(for: ids, in: &draft).indexed, 0)

        let criteria = [
            PhotoQueryCriterion(field: .exifShutterSpeed, comparison: .equals, value: "1/125 s"),
            PhotoQueryCriterion(field: .exifAperture, comparison: .maximum, value: "f/2.8"),
            PhotoQueryCriterion(field: .exifISO, comparison: .minimum, value: "400"),
            PhotoQueryCriterion(field: .exifFocalLength, comparison: .equals, value: "35.5 mm"),
            PhotoQueryCriterion(field: .exifLens, comparison: .contains, value: "test 35")
        ]
        var query = PhotoQuery()
        query.criteria = criteria
        var rule = SmartAlbumRule()
        rule.query = query
        var album = Collection(name: "Capture settings")
        album.rule = rule
        draft.albums = [album]
        XCTAssertEqual(try repo.save(draft).version, 14)

        let originalHash = try LibraryRepository.digest(source)
        let unplugged = temporary.appendingPathComponent("Unplugged.jpg")
        try FileManager.default.moveItem(at: source, to: unplugged)
        var reopened = try repo.load()
        let photo = reopened.photos[0]
        XCTAssertThrowsError(try repo.availableOriginalURL(photo))
        let savedRule = try XCTUnwrap(reopened.albums.first?.rule)
        XCTAssertTrue(savedRule.includes(photo, originalAvailable: {
            XCTFail("An EXIF-only rule tried to read original availability")
            return false
        }))
        XCTAssertEqual(Set(reopened.photos.filter { savedRule.includes($0) }.map(\.id)), [id, sibling.id])
        var reopenedHistory = try XCTUnwrap(reopened.history)
        XCTAssertNotNil(reopenedHistory.step(in: &reopened, redoing: false))
        XCTAssertEqual(reopened.photos[0].caption, "")
        XCTAssertEqual(reopened.photos[0].cameraEXIF, photo.cameraEXIF)
        XCTAssertEqual(try LibraryRepository.digest(unplugged), originalHash)
    }

    private func exifJPEG(_ name: String, exif: [String: Any], orientation: Int = 1) throws -> URL {
        let input = try fixture()
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(input as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let target = temporary.appendingPathComponent(name)
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, pixels, [
            kCGImagePropertyOrientation as String: orientation,
            kCGImagePropertyExifDictionary as String: exif
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return target
    }
}
