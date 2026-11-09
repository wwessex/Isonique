import XCTest
@testable import IsoniqueCore

final class OrganizationTests: XCTestCase {
    func photo(_ name: String) -> Photo {
        Photo(filename: name, originalName: name, projectID: nil, width: 10, height: 10, camera: "Camera", captureDate: "", sha256: "unchanged")
    }
    func testSmartAlbumRequiresEveryRuleAndTracksEdits() {
        var value = photo("Trip.jpg"); value.rating = 4; value.flagged = true; value.keywords = "London"
        let rule = SmartAlbumRule(minimumRating: 3, flaggedOnly: true, text: "london")
        XCTAssertTrue(rule.includes(value))
        value.flagged = false; XCTAssertFalse(rule.includes(value))
        value.flagged = true; value.rating = 2; XCTAssertFalse(rule.includes(value))
        value.rating = 3; value.keywords = "Paris"; XCTAssertFalse(rule.includes(value))
        XCTAssertFalse(SmartAlbumRule().includes({ var p = value; p.rating = -1; return p }()))
    }
    func testBatchUsesStableIDsAndPreservesOtherPhotosAndOriginals() {
        var library = Library(); library.photos = [photo("A.jpg"), photo("B.jpg"), photo("C.jpg")]
        let before = library.photos
        let ids = Set(before.prefix(2).map(\.id)); let stack = UUID()
        let previous = library.updatePhotos(ids) { $0.rating = 99; $0.stackID = stack; $0.adjustments.exposure = 1 }
        XCTAssertEqual(previous, Array(before.prefix(2)))
        XCTAssertEqual(library.photos[2], before[2])
        for index in 0...1 {
            XCTAssertEqual(library.photos[index].rating, 5)
            XCTAssertEqual(library.photos[index].stackID, stack)
            XCTAssertEqual(library.photos[index].filename, before[index].filename)
            XCTAssertEqual(library.photos[index].sha256, before[index].sha256)
        }
        XCTAssertTrue(library.updatePhotos(ids) { $0.rating = 5 }.isEmpty)
    }
    func testRecoveredSmartRatingFiltersPersistAndCombineWithOtherRules() throws {
        let expected: [(RatingFilter, [Int])] = [
            (.all, [-1, 0, 1, 2, 3, 4, 5]), (.unratedAndAbove, [0, 1, 2, 3, 4, 5]),
            (.oneAndAbove, [1, 2, 3, 4, 5]), (.twoAndAbove, [2, 3, 4, 5]),
            (.threeAndAbove, [3, 4, 5]), (.fourAndAbove, [4, 5]),
            (.five, [5]), (.unrated, [0]), (.rejected, [-1])
        ]
        for (filter, ratings) in expected {
            var rule = SmartAlbumRule(flaggedOnly: true, text: "london")
            rule.setRatingFilter(filter)
            let saved = try JSONDecoder().decode(SmartAlbumRule.self, from: JSONEncoder().encode(rule))
            XCTAssertEqual(saved.selectedRatingFilter, filter)
            var value = photo("London.jpg"); value.flagged = true
            XCTAssertEqual((-1...5).filter { value.rating = $0; return saved.includes(value) }, ratings)
            value.rating = ratings[0]; value.flagged = false
            XCTAssertFalse(saved.includes(value))
            value.flagged = true; value.originalName = "Paris.jpg"
            XCTAssertFalse(saved.includes(value))
        }
    }
    func testLegacySmartThresholdRemainsUnchangedAndStackCountUsesActualPhotos() throws {
        let old = Data("{\"minimumRating\":3,\"flaggedOnly\":false,\"text\":\"\"}".utf8)
        let rule = try JSONDecoder().decode(SmartAlbumRule.self, from: old)
        XCTAssertNil(rule.ratingFilterIndex)
        var value = photo("A.jpg")
        XCTAssertEqual((-1...5).filter { value.rating = $0; return rule.includes(value) }, [3, 4, 5])
        let library = Library()
        let staleSelection: Set<UUID> = [UUID(), UUID()]
        let actualPhotos = library.photos.filter { staleSelection.contains($0.id) }
        XCTAssertFalse(StackRules.canStack(photoCount: actualPhotos.count))
        XCTAssertFalse(StackRules.canStack(photoCount: 1))
        XCTAssertTrue(StackRules.canStack(photoCount: 2))
    }
    func testVersionsStacksAndSmartRulesSurviveCatalogueRoundTripAndLegacyDecode() throws {
        var library = Library(); var value = photo("A.jpg")
        var recipe = Adjustments(); recipe.exposure = 1.5
        value.versions = [PhotoVersion(name: "Bright", adjustments: recipe)]; value.stackID = UUID()
        library.photos = [value]
        var album = Collection(name: "Favorites"); album.rule = SmartAlbumRule(minimumRating: 4, flaggedOnly: true)
        library.albums = [album]
        let decoded = try JSONDecoder().decode(Library.self, from: JSONEncoder().encode(library))
        XCTAssertEqual(decoded.photos, library.photos); XCTAssertEqual(decoded.albums, library.albums)
        var oldPhoto = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
        oldPhoto.removeValue(forKey: "versions"); oldPhoto.removeValue(forKey: "stackID")
        let legacy = try JSONDecoder().decode(Photo.self, from: JSONSerialization.data(withJSONObject: oldPhoto))
        XCTAssertNil(legacy.versions); XCTAssertNil(legacy.stackID)
        let oldCollection = try JSONDecoder().decode(Collection.self, from: Data("{\"id\":\"\(UUID().uuidString)\",\"name\":\"Old\"}".utf8))
        XCTAssertNil(oldCollection.rule)
    }
    func testBatchExportDirectoryRejectsLibrariesAndExistingFolders() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let repository = try LibraryRepository(root: root.appendingPathComponent("Managed"))
        let forbidden = repository.root.appendingPathComponent("Export")
        XCTAssertThrowsError(try BatchExport.prepareDirectory(forbidden, repository: repository))
        XCTAssertFalse(FileManager.default.fileExists(atPath: forbidden.path))
        XCTAssertThrowsError(try BatchExport.prepareDirectory(root.appendingPathComponent("Legacy.aplibrary/Export"), repository: repository))
        let folder = root.appendingPathComponent("Export")
        try BatchExport.prepareDirectory(folder, repository: repository)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertThrowsError(try BatchExport.prepareDirectory(folder, repository: repository))
    }
}

extension OrganizationTests {
    func testStackPresentationKeepsFilteredMembersAndIsolatesAlbumOverrides() throws {
        let stack = UUID(), album = UUID(), otherAlbum = UUID()
        var first = Photo(filename: "a.png", originalName: "a.png", projectID: nil, width: 5, height: 5,
                          camera: "", captureDate: "", sha256: "fixture-a")
        var second = Photo(filename: "b.png", originalName: "b.png", projectID: nil, width: 5, height: 5,
                           camera: "", captureDate: "", sha256: "fixture-b")
        first.stackID = stack
        second.stackID = stack
        let unstacked = Photo(filename: "c.png", originalName: "c.png", projectID: nil, width: 5, height: 5,
                              camera: "", captureDate: "", sha256: "fixture-c")
        var library = Library()
        library.photos = [first, second, unstacked]
        library.setStackCollapsed(true, stackID: stack)
        library.applyStackPick(StackPickChange(stackID: stack, photoID: second.id, selectionID: second.id))
        let previous = library.applyStackPick(StackPickChange(stackID: stack, albumID: album,
                                                              photoID: first.id, selectionID: first.id))
        XCTAssertNil(previous.photoID)
        let encoded = try JSONEncoder().encode(library)
        let state = try XCTUnwrap(JSONDecoder().decode(Library.self, from: encoded).stackBrowser)
        XCTAssertEqual(state.presenting([first, unstacked, second], albumID: album), [first, unstacked])
        XCTAssertEqual(state.presenting([first, unstacked, second], albumID: otherAlbum), [second, unstacked])
        XCTAssertEqual(state.presenting([first, unstacked], albumID: nil), [first, unstacked])
    }
}
