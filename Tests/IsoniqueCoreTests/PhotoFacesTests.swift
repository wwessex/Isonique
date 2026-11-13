import CoreImage
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class PhotoFacesTests: XCTestCase {
    func testVisionCoordinatesClipAndRescanningRespectsManualCorrections() throws {
        let left = try XCTUnwrap(FaceRegion(visionRect: CGRect(x: -0.03, y: 0.55, width: 0.23, height: 0.25)))
        XCTAssertEqual(left.x, 0)
        XCTAssertEqual(left.y, 0.2, accuracy: 0.000001)
        XCTAssertEqual(left.width, 0.2, accuracy: 0.000001)
        let right = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.7, y: 0.25, width: 0.2, height: 0.25)))
        let corrected = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.4, y: 0.7, width: 0.2, height: 0.25)))
        XCTAssertNil(FaceRegion(imageRect: .infinite))
        XCTAssertNil(FaceRegion(imageRect: CGRect(x: 1.2, y: 0, width: 0.1, height: 0.2)))

        var people = PhotoPeople()
        people.incorporateDetections([left, right, left])
        XCTAssertTrue(people.scanned)
        XCTAssertEqual(people.faces.count, 2)
        let keptID = people.faces[1].id
        people.faces[1].assignName("  Zoë  Rivera \n")
        people.removeFace(people.faces[0].id)
        people.moveFace(keptID, to: corrected)
        let reopened = try JSONDecoder().decode(PhotoPeople.self, from: JSONEncoder().encode(people))
        people = reopened
        people.incorporateDetections([right, left, corrected])
        XCTAssertEqual(people.faces.map(\.id), [keptID])
        XCTAssertEqual(people.faces.first?.name, "Zoë Rivera")
        XCTAssertEqual(people.faces.first?.region, corrected)
    }

    func testPeopleHistoryAndRulesRequireFormat37AndProtectOlderProjectExports() throws {
        let photo = Photo(filename: "a.jpg", originalName: "a.jpg", projectID: nil,
                          width: 120, height: 80, camera: "", captureDate: "", sha256: "fixture")
        var legacy = Library()
        legacy.version = 36
        legacy.photos = [photo]
        let data = try JSONEncoder().encode(legacy)
        XCTAssertNil(try LibraryBackup.decodeCatalogue(data).photos.first?.people)

        var rule = SmartAlbumRule()
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .person, comparison: .isMissing)]
        rule.query = query
        var album = Collection(name: "Unassigned")
        album.rule = rule
        legacy.albums = [album]
        XCTAssertThrowsError(try legacy.validateSchema())
        legacy.upgradeForPeople()
        XCTAssertEqual(legacy.version, 37)
        try legacy.validateSchema()

        var current = photo
        let region = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)))
        var people = PhotoPeople()
        people.incorporateDetections([region])
        people.faces[0].assignName("Current")
        current.people = people
        var history = EditHistory()
        history.record(.people([PhotoPeopleChange(photoID: current.id, people: people)]))
        legacy.albums = []
        legacy.history = history
        legacy.version = 36
        XCTAssertThrowsError(try legacy.validateSchema())
        legacy.version = 37
        try legacy.validateSchema()
        var incoming = photo
        people.faces[0].assignName("Incoming")
        incoming.people = people
        let baseline = ProjectPhotoMergeValues(photo)
        XCTAssertEqual(baseline.merging(current, with: photo, prefer: .incoming, representedAlbums: []).photo.people, current.people)
        let merged = baseline.merging(current, with: incoming, prefer: .incoming, representedAlbums: [], supportsPeople: true)
        XCTAssertEqual(merged.photo.people, incoming.people)
        XCTAssertEqual(merged.conflicts, ["People"])
        XCTAssertEqual(baseline.merging(current, with: incoming, prefer: .current, representedAlbums: [],
                                        supportsPeople: true).photo.people, current.people)
    }

    func testVisionDetectsMultipleFacesWithRotatedAndMirroredEXIF() async throws {
        // A public example is NASA's STS-7 crew portrait, S83-29016. Keep fixtures local.
        guard let path = ProcessInfo.processInfo.environment["ISONIQUE_VISION_GROUP_FIXTURE"] else {
            throw XCTSkip("Set ISONIQUE_VISION_GROUP_FIXTURE to an upright group JPEG")
        }
        let source = URL(fileURLWithPath: path)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }

        let upright = try FaceDetection.sourcePreview(at: source)
        let expected = try await FaceDetection.regions(in: upright)
        XCTAssertGreaterThanOrEqual(expected.count, 2)
        let context = CIContext()
        let image = CIImage(cgImage: upright)

        for (physical, exif) in [(CGImagePropertyOrientation.left, CGImagePropertyOrientation.right),
                                 (.upMirrored, .upMirrored)] {
            let rotated = image.oriented(physical)
            let pixels = try XCTUnwrap(context.createCGImage(rotated, from: rotated.extent))
            let target = folder.appendingPathComponent("\(exif.rawValue).jpg")
            let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, pixels, [
                kCGImagePropertyOrientation: exif.rawValue,
                kCGImageDestinationLossyCompressionQuality: 0.98
            ] as CFDictionary)
            XCTAssertTrue(CGImageDestinationFinalize(destination))
            let oriented = try FaceDetection.sourcePreview(at: target)
            XCTAssertEqual(oriented.width, upright.width)
            XCTAssertEqual(oriented.height, upright.height)
            let detections = try await FaceDetection.regions(in: oriented)
            XCTAssertEqual(detections.count, expected.count)
            for face in expected {
                XCTAssertTrue(detections.contains { face.overlapsFace($0) }, "EXIF orientation \(exif.rawValue)")
            }
        }
    }
}
