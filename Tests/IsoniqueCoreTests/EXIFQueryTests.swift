import ImageIO
import XCTest
@testable import IsoniqueCore

final class EXIFQueryTests: XCTestCase {
    private var photo: Photo {
        var photo = Photo(filename: "photo.nef", originalName: "photo.nef", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "photo")
        photo.cameraEXIF = CameraEXIF(properties: [kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifExposureTime as String: 1.0 / 125,
            kCGImagePropertyExifFNumber as String: Double(Float(6.7)),
            kCGImagePropertyExifISOSpeedRatings as String: [1000],
            kCGImagePropertyExifFocalLength as String: 35.5,
            kCGImagePropertyExifLensModel as String: "Léns 35–70 mm"
        ]])
        return photo
    }

    func testTypedEXIFRulesCompareNumbersAndLensText() {
        let photo = photo
        let matches: [(PhotoQueryField, PhotoQueryOperator, String)] = [
            (.exifShutterSpeed, .equals, "1/125 s"), (.exifShutterSpeed, .equals, "0.008"),
            (.exifShutterSpeed, .minimum, "1 / 250"), (.exifShutterSpeed, .maximum, "0.01 s"),
            (.exifAperture, .equals, "f/6,7"), (.exifAperture, .minimum, "ƒ/6.7"),
            (.exifISO, .minimum, "800"), (.exifFocalLength, .equals, "35.5 mm"),
            (.exifFocalLength, .differs, "35"), (.exifLens, .contains, "LENS"),
            (.exifLens, .excludes, "macro")
        ]
        for (field, comparison, value) in matches {
            let rule = PhotoQueryCriterion(field: field, comparison: comparison, value: value)
            XCTAssertTrue(rule.isValid, value)
            XCTAssertTrue(rule.includes(photo, originalAvailable: { false }), value)
        }
        let nonmatches: [(PhotoQueryField, PhotoQueryOperator, String)] = [
            (.exifShutterSpeed, .maximum, "1/250"), (.exifAperture, .differs, "6.7"),
            (.exifISO, .maximum, "800"), (.exifFocalLength, .minimum, "40 mm"),
            (.exifLens, .equals, "lens")
        ]
        for (field, comparison, value) in nonmatches {
            XCTAssertFalse(PhotoQueryCriterion(field: field, comparison: comparison, value: value)
                .includes(photo, originalAvailable: { false }), value)
        }
        let invalid: [(PhotoQueryField, String)] = [
            (.exifShutterSpeed, "1/0"), (.exifShutterSpeed, "1/125/2"), (.exifShutterSpeed, "NaN"),
            (.exifAperture, "0"), (.exifAperture, "-2"), (.exifISO, "400.5"),
            (.exifISO, "0"), (.exifFocalLength, "35 cm"), (.exifFocalLength, "inf"), (.exifLens, "")
        ]
        for (field, value) in invalid {
            let rule = PhotoQueryCriterion(field: field, comparison: .equals, value: value)
            XCTAssertFalse(rule.isValid, value)
            XCTAssertFalse(rule.includes(photo, originalAvailable: { false }), value)
        }
    }

    func testMissingValuesRequireAnExplicitPresenceRule() {
        let populated = photo
        var missing = photo
        missing.cameraEXIF = nil
        var checkedEmpty = photo
        checkedEmpty.cameraEXIF = CameraEXIF(properties: [:])
        for field in PhotoQueryField.allCases.filter(\.isEXIF) {
            let absent = PhotoQueryCriterion(field: field, comparison: .isMissing)
            let present = PhotoQueryCriterion(field: field, comparison: .isPresent)
            let differs = PhotoQueryCriterion(field: field, comparison: .differs, value: "1")
            XCTAssertTrue(absent.isValid)
            XCTAssertTrue(present.isValid)
            XCTAssertTrue(absent.includes(missing, originalAvailable: { false }))
            XCTAssertTrue(absent.includes(checkedEmpty, originalAvailable: { false }))
            XCTAssertTrue(present.includes(populated, originalAvailable: { false }))
            XCTAssertFalse(present.includes(missing, originalAvailable: { false }))
            XCTAssertFalse(differs.includes(missing, originalAvailable: { false }))
        }
        XCTAssertFalse(PhotoQueryCriterion(field: .filename, comparison: .isMissing).isValid)
        XCTAssertFalse(PhotoQueryCriterion(field: .exifLens, comparison: .excludes, value: "zoom")
            .includes(missing, originalAvailable: { false }))
    }

    func testSavingAnEXIFRuleUpgradesACatalogueWithoutCaptureValues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueEXIFRules-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .exifLens, comparison: .isMissing)]
        var album = Collection(name: "Missing lens")
        album.rule = SmartAlbumRule()
        album.rule?.query = query
        library.albums = [album]
        XCTAssertEqual(try repository.save(library).version, 14)
        XCTAssertEqual(try repository.load().albums.first?.rule?.query, query)
    }
}
