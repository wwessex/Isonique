import XCTest
@testable import IsoniqueCore

final class LibraryBackupTests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: folder) }
    private func fixture() throws -> LibraryRepository {
        let repo = try LibraryRepository(root: folder.appendingPathComponent("library"))
        let original = repo.root.appendingPathComponent("Originals/photo.jpg")
        try Data("immutable original bytes".utf8).write(to: original)
        var library = Library()
        var photo = Photo(filename: "photo.jpg", originalName: "Camera.jpg", projectID: nil,
                          width: 20, height: 10, camera: "Camera", captureDate: "", sha256: try LibraryRepository.digest(original))
        photo.caption = "Keep this caption"; photo.adjustments.exposure = 1.2
        photo.versions = [PhotoVersion(name: "First edit", adjustments: photo.adjustments)]
        library.photos = [photo]; library.albums = [Collection(name: "Favorites")]
        library.photos[0].albumIDs = [library.albums[0].id]
        var history = EditHistory(); history.record(photo); library.history = history
        try repo.save(library)
        return repo
    }
    func testVerifiedBackupRestorePreservesAllCatalogueDataAndOriginals() throws {
        let repo = try fixture()
        let backup = folder.appendingPathComponent("backup"), restored = folder.appendingPathComponent("restored")
        let catalogBefore = try Data(contentsOf: repo.root.appendingPathComponent("catalog.json"))
        try LibraryBackup.create(from: repo, to: backup)
        XCTAssertEqual(try LibraryBackup.validateBackup(backup), 1)
        try LibraryBackup.restore(from: backup, to: restored, excluding: repo.root)
        let (restoredRepo, opened) = try LibraryBackup.openVerified(restored)
        XCTAssertEqual(opened.photos.count, 1)
        XCTAssertEqual(try LibraryBackup.verify(restoredRepo), 1)
        XCTAssertEqual(try Data(contentsOf: restored.appendingPathComponent("catalog.json")), catalogBefore)
        XCTAssertEqual(try Data(contentsOf: repo.root.appendingPathComponent("catalog.json")), catalogBefore)
        XCTAssertEqual(try restoredRepo.load().photos, try repo.load().photos)
        XCTAssertEqual(try Data(contentsOf: restored.appendingPathComponent("Originals/photo.jpg")), Data("immutable original bytes".utf8))
    }
    func testCorruptedOriginalFailsCheckAndLeavesNoBackup() throws {
        let repo = try fixture(), target = folder.appendingPathComponent("backup")
        try Data("changed".utf8).write(to: repo.root.appendingPathComponent("Originals/photo.jpg"))
        XCTAssertThrowsError(try LibraryBackup.verify(repo))
        XCTAssertThrowsError(try LibraryBackup.openVerified(repo.root))
        XCTAssertThrowsError(try LibraryBackup.create(from: repo, to: target))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
    func testTamperedCatalogueAndMissingOriginalRefuseRestore() throws {
        let repo = try fixture(), backup = folder.appendingPathComponent("backup")
        try LibraryBackup.create(from: repo, to: backup)
        let catalog = backup.appendingPathComponent("catalog.json")
        let saved = try Data(contentsOf: catalog)
        var tampered = try JSONDecoder().decode(Library.self, from: saved)
        tampered.photos[0].caption = "tampered"
        try JSONEncoder().encode(tampered).write(to: catalog)
        let target = folder.appendingPathComponent("restored")
        XCTAssertThrowsError(try LibraryBackup.restore(from: backup, to: target, excluding: repo.root))
        try saved.write(to: catalog)
        try FileManager.default.removeItem(at: backup.appendingPathComponent("Originals/photo.jpg"))
        XCTAssertThrowsError(try LibraryBackup.restore(from: backup, to: target, excluding: repo.root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }
    func testExistingNestedLegacyAndSymlinkDestinationsAreProtected() throws {
        let repo = try fixture()
        let existing = folder.appendingPathComponent("existing")
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let sentinel = existing.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        for target in [existing, repo.root, repo.root.appendingPathComponent("nested"), folder.appendingPathComponent("Old.aplibrary/backup")] {
            XCTAssertThrowsError(try LibraryBackup.create(from: repo, to: target))
        }
        let link = folder.appendingPathComponent("linked")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: repo.root)
        XCTAssertThrowsError(try LibraryBackup.create(from: repo, to: link.appendingPathComponent("nested")))
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep".utf8))
        let original = repo.root.appendingPathComponent("Originals/photo.jpg")
        let outside = folder.appendingPathComponent("outside.jpg")
        try FileManager.default.moveItem(at: original, to: outside)
        try FileManager.default.createSymbolicLink(at: original, withDestinationURL: outside)
        XCTAssertThrowsError(try LibraryBackup.verify(repo))
    }
    func testEmptyLibraryBackup() throws {
        let repo = try LibraryRepository(root: folder.appendingPathComponent("empty"))
        try repo.save(Library())
        let backup = folder.appendingPathComponent("backup")
        try LibraryBackup.create(from: repo, to: backup)
        try LibraryBackup.restore(from: backup, to: folder.appendingPathComponent("restored"), excluding: repo.root)
        XCTAssertEqual(try LibraryBackup.verify(repo), 0)
    }

    func testBackupPreflightRejectsUnsupportedVersionsAndCorruptSourcesWithoutWriting() throws {
        let repo = try fixture(), backup = folder.appendingPathComponent("backup")
        try LibraryBackup.create(from: repo, to: backup)
        let manifestURL = backup.appendingPathComponent("backup-manifest.json")
        let saved = try Data(contentsOf: manifestURL)
        var manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        for version in [0, 2] {
            manifest["version"] = version
            try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
            XCTAssertThrowsError(try LibraryBackup.validateBackup(backup))
        }
        try saved.write(to: manifestURL)
        let catalogURL = backup.appendingPathComponent("catalog.json")
        var catalog = try repo.load(); catalog.version = 7
        try JSONEncoder().encode(catalog).write(to: catalogURL)
        // Keep the manifest hash consistent to exercise the catalogue version guard.
        manifest["version"] = 1
        manifest["catalogSHA256"] = try LibraryRepository.digest(catalogURL)
        try JSONSerialization.data(withJSONObject: manifest).write(to: manifestURL)
        XCTAssertThrowsError(try LibraryBackup.validateBackup(backup))
        let target = folder.appendingPathComponent("restored")
        XCTAssertThrowsError(try LibraryBackup.restore(from: backup, to: target, excluding: repo.root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try LibraryBackup.verify(repo), 1)
    }
}
