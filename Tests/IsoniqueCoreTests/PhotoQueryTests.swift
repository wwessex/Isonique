import XCTest
@testable import IsoniqueCore

final class PhotoQueryTests: XCTestCase {
    private func fixture() -> Photo {
        var photo = Photo(filename: "managed.jpeg", originalName: "Studio-IMG_0001.jpeg", projectID: UUID(),
                          width: 1600, height: 900, camera: "Camera Z", captureDate: "2024:02:29 17:30:00", sha256: "fixture")
        photo.sourceName = "IMG_0001.jpeg"
        photo.keywords = "Café, Travel"
        photo.rating = 4
        return photo
    }

    func testRuleMatchingUsesExactKeywordsNormalizedExtensionsAndAllOrAny() {
        let photo = fixture()
        var query = PhotoQuery()
        query.criteria = [
            PhotoQueryCriterion(field: .keyword, comparison: .equals, value: "CAFE"),
            PhotoQueryCriterion(field: .filename, comparison: .equals, value: "img_0001.jpeg"),
            PhotoQueryCriterion(field: .format, comparison: .equals, value: ".JPG"),
            PhotoQueryCriterion(field: .rating, comparison: .minimum, value: "4")
        ]
        XCTAssertTrue(query.criteria.allSatisfy(\.isValid))
        XCTAssertTrue(query.includes(photo))
        query.criteria[0].value = "Tra"
        XCTAssertFalse(query.includes(photo))
        query.match = .any
        XCTAssertTrue(query.includes(photo))
        query.criteria[0].comparison = .contains
        query.match = .all
        XCTAssertTrue(query.includes(photo))
        query.criteria[0].comparison = .excludes
        XCTAssertFalse(query.includes(photo))
    }

    func testCaptureDateAndAvailabilityMatchOnlyKnownValues() {
        var photo = fixture()
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .captured, comparison: .since, value: "2024-02-29")]
        XCTAssertTrue(query.includes(photo))
        query.criteria[0].value = "2024-03-01"
        XCTAssertFalse(query.includes(photo))
        query.criteria[0].value = "2023-02-29"
        XCTAssertFalse(query.criteria[0].isValid)
        XCTAssertFalse(query.includes(photo))
        query.criteria[0] = PhotoQueryCriterion(field: .captured, comparison: .differs, value: "2024-03-01")
        photo.captureDate = ""
        XCTAssertFalse(query.includes(photo))

        query.criteria = [PhotoQueryCriterion(field: .availability, comparison: .equals, value: "false")]
        XCTAssertFalse(query.includes(photo))
        XCTAssertFalse(query.includes(photo, originalAvailable: { true }))
        XCTAssertTrue(query.includes(photo, originalAvailable: { false }))
    }

    func testSavedCompoundRuleKeepsBasicFiltersAndProjectScope() throws {
        var photo = fixture()
        var query = PhotoQuery()
        query.match = .any
        query.criteria = [
            PhotoQueryCriterion(field: .flag, comparison: .equals, value: "true"),
            PhotoQueryCriterion(field: .adjusted, comparison: .equals, value: "true")
        ]
        var rule = SmartAlbumRule(minimumRating: 3, text: "camera")
        rule.projectID = photo.projectID
        rule.query = query
        let restored = try JSONDecoder().decode(SmartAlbumRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(restored, rule)
        XCTAssertFalse(restored.includes(photo))
        photo.adjustments.exposure = 0.5
        XCTAssertTrue(restored.includes(photo))
        photo.rating = 2
        XCTAssertFalse(restored.includes(photo))
        photo.rating = 5
        photo.projectID = UUID()
        XCTAssertFalse(restored.includes(photo))

        let old = try JSONDecoder().decode(SmartAlbumRule.self, from: Data(#"{"minimumRating":3,"flaggedOnly":false,"text":"camera"}"#.utf8))
        XCTAssertNil(old.query)
        XCTAssertNil(old.projectID)
        XCTAssertTrue(old.includes(photo))
    }
}
