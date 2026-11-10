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
