import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testGPSParsesDecimalDegreesAndHemisphereReferences() throws {
        let northWest = try XCTUnwrap(GPSCoordinates(properties: gpsProperties(51.5, "N", 0.125, "W")))
        XCTAssertEqual(northWest.latitude, 51.5)
        XCTAssertEqual(northWest.longitude, -0.125)

        let southEast = try XCTUnwrap(GPSCoordinates(properties: gpsProperties(33.875, " s ", 151.25, "e")))
        XCTAssertEqual(southEast.latitude, -33.875)
        XCTAssertEqual(southEast.longitude, 151.25)

        let signed = try XCTUnwrap(GPSCoordinates(properties: gpsProperties(-90, "S", -180, "W")))
        XCTAssertEqual(signed.latitude, -90)
        XCTAssertEqual(signed.longitude, -180)

        let zero = try XCTUnwrap(GPSCoordinates(properties: gpsProperties(0, "S", 0, "W")))
        XCTAssertEqual(zero.latitude.sign, .plus)
        XCTAssertEqual(zero.longitude.sign, .plus)
        XCTAssertEqual(zero.latitude, 0)
        XCTAssertEqual(zero.longitude, 0)
    }

    func testGPSRejectsMissingPartialAndInvalidCoordinates() {
        XCTAssertNil(GPSCoordinates(properties: [:]))
        let invalid = [
            gpsProperties(nil, "N", 10, "E"),
            gpsProperties(10, "N", nil, "E"),
            gpsProperties(10, nil, 10, "E"),
            gpsProperties(10, "N", 10, nil),
            gpsProperties(10, "W", 10, "E"),
            gpsProperties(10, "N", 10, "S"),
            gpsProperties(-10, "N", 10, "E"),
            gpsProperties(10, "N", -10, "E"),
            gpsProperties(90.1, "N", 10, "E"),
            gpsProperties(10, "N", 180.1, "E"),
            gpsProperties(Double.nan, "N", 10, "E"),
            gpsProperties(10, "N", Double.infinity, "W"),
            gpsProperties(true, "N", 10, "E"),
            gpsProperties(10, "N", "20", "E")
        ]
        for (index, properties) in invalid.enumerated() {
            XCTAssertNil(GPSCoordinates(properties: properties), "Invalid GPS case \(index)")
        }
    }

    func testGPSReadsEmbeddedJPEGAndTIFFAndDistinguishesOfflineAndUnreadableOriginals() throws {
        let taggedJPEG = try gpsImage("Sydney.jpg", type: .jpeg, properties: gpsProperties(33.875, "S", 151.25, "E"))
        let taggedTIFF = try gpsImage("London.tiff", type: .tiff, properties: gpsProperties(51.5, "N", 0.125, "W"))
        let untaggedJPEG = try gpsImage("Untagged.jpg", type: .jpeg, properties: [:])
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        var options = ImportOptions()
        options.storage = .referenced
        XCTAssertTrue(try repository.importPhoto(taggedJPEG, projectID: nil, into: &library, options: options))
        XCTAssertTrue(try repository.importPhoto(taggedTIFF, projectID: nil, into: &library))
        XCTAssertTrue(try repository.importPhoto(untaggedJPEG, projectID: nil, into: &library))

        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let originalHashes = try [taggedJPEG, taggedTIFF, untaggedJPEG].map(LibraryRepository.digest)
        let catalogueBefore = try Data(contentsOf: catalogue)
        library = try repository.load()
        let sydney = try XCTUnwrap(library.photos.first { $0.originalName == "Sydney.jpg" })
        let london = try XCTUnwrap(library.photos.first { $0.originalName == "London.tiff" })
        let untagged = try XCTUnwrap(library.photos.first { $0.originalName == "Untagged.jpg" })
        let sydneyGPS = try XCTUnwrap(repository.originalMetadata(for: sydney).gps)
        let londonGPS = try XCTUnwrap(repository.originalMetadata(for: london).gps)
        XCTAssertEqual(sydneyGPS.latitude, -33.875, accuracy: 0.000001)
        XCTAssertEqual(sydneyGPS.longitude, 151.25, accuracy: 0.000001)
        XCTAssertEqual(londonGPS.latitude, 51.5, accuracy: 0.000001)
        XCTAssertEqual(londonGPS.longitude, -0.125, accuracy: 0.000001)
        XCTAssertNil(try repository.originalMetadata(for: untagged).gps)

        let fm = FileManager.default
        let parked = temporary.appendingPathComponent("Offline.jpg")
        try fm.moveItem(at: taggedJPEG, to: parked)
        XCTAssertThrowsError(try repository.originalMetadata(for: sydney)) { error in
            guard case LibraryError.originalUnavailable(_) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        try Data("not an image".utf8).write(to: taggedJPEG)
        XCTAssertThrowsError(try repository.originalMetadata(for: sydney)) { error in
            guard case LibraryError.unsupportedImage(_) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        try fm.removeItem(at: taggedJPEG)
        try fm.moveItem(at: parked, to: taggedJPEG)
        XCTAssertEqual(try repository.originalMetadata(for: sydney).gps, sydneyGPS)
        let managed = try repository.originalURL(london)
        try fm.moveItem(at: managed, to: parked)
        XCTAssertThrowsError(try repository.originalMetadata(for: london)) { error in
            guard case LibraryError.originalUnavailable(_) = error else { return XCTFail("Unexpected error: \(error)") }
        }
        try fm.moveItem(at: parked, to: managed)
        XCTAssertEqual(try repository.originalMetadata(for: london).gps, londonGPS)

        XCTAssertEqual(try Data(contentsOf: catalogue), catalogueBefore)
        XCTAssertEqual(try [taggedJPEG, managed, untaggedJPEG].map(LibraryRepository.digest), originalHashes)
    }

    func testGPSIndexBackfillsSelectedOriginalsAndSearchesOfflineAfterReopening() throws {
        let sydney = try gpsImage("Sydney.jpg", type: .jpeg, properties: gpsProperties(33.875, "S", 151.25, "E"))
        let untagged = try gpsImage("Untagged.jpg", type: .jpeg, properties: [:])
        let replaced = try gpsImage("Replaced.jpg", type: .jpeg, properties: gpsProperties(30, "N", 31, "E"))
        let unselected = try gpsImage("Unselected.jpg", type: .jpeg, properties: gpsProperties(45, "N", 73, "W"))
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        var options = ImportOptions()
        options.storage = .referenced
        for original in [sydney, untagged, replaced, unselected] {
            XCTAssertTrue(try repository.importPhoto(original, projectID: nil, into: &library, options: options))
        }
        let id = library.photos[0].id
        let imported = try XCTUnwrap(library.photos[0].gpsIndex?.coordinates)
        XCTAssertEqual(try repository.load().version, 15)
        XCTAssertEqual(try repository.originalMetadata(for: library.photos[0]).gps, imported)
        XCTAssertNotNil(library.photos[1].gpsIndex)
        XCTAssertNil(library.photos[1].gpsIndex?.coordinates)

        for index in library.photos.indices { library.photos[index].gpsIndex = nil }
        library.version = 14
        let sibling = try XCTUnwrap(library.createVersion(of: id, from: .current))
        var history = EditHistory()
        history.record(library.photos[0])
        library.photos[0].caption = "Edited before indexing"
        library.history = history
        library = try repository.save(library)
        XCTAssertEqual(try repository.load().version, 14)
        let oldFingerprint = try LibraryRepository.digest(sydney)
        try Data(contentsOf: unselected).write(to: replaced)

        let targets: Set<UUID> = [id, library.photos[1].id, library.photos[2].id]
        let indexed = try repository.catalogueGPS(for: targets, in: &library)
        XCTAssertEqual(indexed.indexed, 3)
        XCTAssertEqual(indexed.withValues, 2)
        XCTAssertEqual(indexed.issues.count, 1)
        XCTAssertTrue(indexed.issues.first?.contains("Replaced.jpg") == true)
        XCTAssertEqual(library.photos.first { $0.id == sibling.id }?.gpsIndex?.coordinates, imported)
        XCTAssertNotNil(library.photos[1].gpsIndex)
        XCTAssertNil(library.photos[2].gpsIndex)
        XCTAssertNil(library.photos[3].gpsIndex)
        XCTAssertEqual(try repository.catalogueGPS(for: [id], in: &library).indexed, 0)

        var query = PhotoQuery()
        query.criteria = [
            PhotoQueryCriterion(field: .gpsLocation, comparison: .withinRadius,
                                gpsRadius: GPSRadiusRule(latitude: "-33.875", longitude: "151.25", kilometres: "5")),
            PhotoQueryCriterion(field: .gpsLatitude, comparison: .maximum, value: "-30")
        ]
        var rule = SmartAlbumRule()
        rule.query = query
        var album = Collection(name: "Sydney area")
        album.rule = rule
        library.albums = [album]
        XCTAssertEqual(try repository.save(library).version, 15)

        let parked = temporary.appendingPathComponent("Offline.jpg")
        try FileManager.default.moveItem(at: sydney, to: parked)
        var reopened = try repository.load()
        XCTAssertThrowsError(try repository.availableOriginalURL(reopened.photos[0]))
        let savedRule = try XCTUnwrap(reopened.albums.first?.rule)
        XCTAssertEqual(savedRule.query, query)
        XCTAssertEqual(Set(reopened.activePhotos.filter { photo in
            savedRule.includes(photo, originalAvailable: {
                XCTFail("A GPS rule checked original availability")
                return false
            })
        }.map(\.id)), [id, sibling.id])
        let missing = PhotoQueryCriterion(field: .gpsLocation, comparison: .isMissing)
        let unindexed = PhotoQueryCriterion(field: .gpsLocation, comparison: .isUnindexed)
        XCTAssertTrue(missing.includes(reopened.photos[1], originalAvailable: { false }))
        XCTAssertFalse(unindexed.includes(reopened.photos[1], originalAvailable: { false }))
        XCTAssertFalse(missing.includes(reopened.photos[2], originalAvailable: { false }))
        XCTAssertTrue(unindexed.includes(reopened.photos[2], originalAvailable: { false }))
        var reopenedHistory = try XCTUnwrap(reopened.history)
        XCTAssertNotNil(reopenedHistory.step(in: &reopened, redoing: false))
        XCTAssertEqual(reopened.photos[0].caption, "")
        XCTAssertEqual(reopened.photos[0].gpsIndex?.coordinates, imported)
        XCTAssertEqual(try LibraryRepository.digest(parked), oldFingerprint)
    }

    func testGPSRulesValidateCoordinatesAndMatchAcrossTheDateLine() throws {
        let west = GPSIndex(properties: gpsProperties(0, "N", 179.9, "W"))
        var photo = Photo(filename: "Dateline.jpg", originalName: "Dateline.jpg", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "original")
        photo.gpsIndex = west

        var radius = PhotoQueryCriterion(field: .gpsLocation, comparison: .withinRadius,
                                        gpsRadius: GPSRadiusRule(latitude: "0", longitude: "179,9°", kilometres: "23"))
        XCTAssertTrue(radius.isValid)
        XCTAssertTrue(radius.includes(photo, originalAvailable: { nil }))
        radius.gpsRadius?.kilometres = "22"
        XCTAssertFalse(radius.includes(photo, originalAvailable: { nil }))
        radius.gpsRadius?.kilometres = "0"
        XCTAssertFalse(radius.isValid)
        XCTAssertFalse(radius.includes(photo, originalAvailable: { nil }))
        radius.gpsRadius = GPSRadiusRule(latitude: "91", longitude: "179.9", kilometres: "23")
        XCTAssertFalse(radius.isValid)

        let longitude = PhotoQueryCriterion(field: .gpsLongitude, comparison: .equals, value: "−179,900000°")
        XCTAssertTrue(longitude.isValid)
        XCTAssertTrue(longitude.includes(photo, originalAvailable: { nil }))
        XCTAssertTrue(PhotoQueryCriterion(field: .gpsLongitude, comparison: .minimum, value: "-180")
            .includes(photo, originalAvailable: { nil }))
        XCTAssertFalse(PhotoQueryCriterion(field: .gpsLongitude, comparison: .maximum, value: "-180")
            .includes(photo, originalAvailable: { nil }))
        XCTAssertFalse(PhotoQueryCriterion(field: .gpsLongitude, comparison: .maximum, value: "-180.00001").isValid)
        XCTAssertFalse(PhotoQueryCriterion(field: .gpsLatitude, comparison: .equals, value: "NaN").isValid)
        let hasGPS = PhotoQueryCriterion(field: .gpsLocation, comparison: .isPresent)
        XCTAssertTrue(hasGPS.includes(photo, originalAvailable: { nil }))
        photo.gpsIndex = nil
        XCTAssertFalse(hasGPS.includes(photo, originalAvailable: { nil }))
        XCTAssertFalse(PhotoQueryCriterion(field: .gpsLongitude, comparison: .differs, value: "0")
            .includes(photo, originalAvailable: { nil }))
        let invalid = Data(#"{"latitude": 91, "longitude": 0}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(GPSCoordinates.self, from: invalid))
    }

    func testSavedGPSRuleRequiresNewCatalogueFormatWithoutCoordinates() throws {
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .gpsLocation, comparison: .isUnindexed)]
        var album = Collection(name: "GPS to check")
        album.rule = SmartAlbumRule()
        album.rule?.query = query
        library.albums = [album]
        XCTAssertEqual(try repository.save(library).version, 15)
        XCTAssertEqual(try repository.load().albums.first?.rule?.query, query)
    }

    private func gpsProperties(_ latitude: Any?, _ latitudeRef: String?,
                               _ longitude: Any?, _ longitudeRef: String?) -> [String: Any] {
        let gps: [String: Any?] = [
            kCGImagePropertyGPSLatitude as String: latitude,
            kCGImagePropertyGPSLatitudeRef as String: latitudeRef,
            kCGImagePropertyGPSLongitude as String: longitude,
            kCGImagePropertyGPSLongitudeRef as String: longitudeRef
        ]
        return [kCGImagePropertyGPSDictionary as String: gps.compactMapValues { $0 }]
    }

    private func gpsImage(_ name: String, type: UTType, properties: [String: Any]) throws -> URL {
        let input = try fixture()
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(input as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let target = temporary.appendingPathComponent(name)
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(target as CFURL, type.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, pixels, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return target
    }
}
