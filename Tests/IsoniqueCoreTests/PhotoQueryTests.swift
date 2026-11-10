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

    func testColorLabelRuleUsesStableColorAndSupportsUnlabelled() throws {
        var photo = fixture()
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .colorLabel, comparison: .equals, value: "0")]
        XCTAssertTrue(query.includes(photo))
        photo.colorLabel = .blue
        XCTAssertFalse(query.includes(photo))
        query.criteria[0].value = String(PhotoColorLabel.blue.rawValue)
        let restored = try JSONDecoder().decode(PhotoQuery.self, from: JSONEncoder().encode(query))
        XCTAssertTrue(restored.includes(photo))
        query.criteria[0].value = "9"
        XCTAssertFalse(query.criteria[0].isValid)
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

    func testIPTCRulesMatchEachFieldAndCreatorIndividually() throws {
        var photo = fixture()
        photo.iptc = IPTCMetadata(title: "Harbour", creators: ["Jo Weiß", "Alex Ng"],
                                  copyright: "© 2026 Róisín", credit: "News Desk")
        var query = PhotoQuery()
        query.criteria = [
            PhotoQueryCriterion(field: .iptcTitle, comparison: .equals, value: " harbour "),
            PhotoQueryCriterion(field: .iptcCreator, comparison: .equals, value: "alex ng"),
            PhotoQueryCriterion(field: .iptcCopyright, comparison: .contains, value: "roisin"),
            PhotoQueryCriterion(field: .iptcCredit, comparison: .excludes, value: "wire")
        ]
        XCTAssertTrue(query.criteria.allSatisfy(\.isValid))
        let decoded = try JSONDecoder().decode(PhotoQuery.self, from: JSONEncoder().encode(query))
        XCTAssertTrue(decoded.includes(photo))
        query.criteria[1].value = "Jo Weiß Alex Ng"
        XCTAssertFalse(query.includes(photo))
        query.criteria[1] = PhotoQueryCriterion(field: .iptcCreator, comparison: .differs, value: "Alex Ng")
        XCTAssertFalse(query.includes(photo))
        query.match = .any
        XCTAssertTrue(query.includes(photo))
        photo.iptc = nil
        XCTAssertTrue(query.includes(photo))
        query.match = .all
        XCTAssertFalse(query.includes(photo))
    }

    func testSavedIPTCRuleUpgradesEvenWithoutIPTCPhotos() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueIPTCRules-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository.createEmpty(at: root)
        var library = try repository.load()
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .iptcCredit, comparison: .equals, value: "Desk")]
        var rule = SmartAlbumRule()
        rule.query = query
        var album = Collection(name: "News")
        album.rule = rule
        library.albums = [album]
        XCTAssertEqual(try repository.save(library).version, 12)
        XCTAssertEqual(try repository.load().albums.first?.rule, rule)
    }
}
