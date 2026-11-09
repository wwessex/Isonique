import XCTest
@testable import IsoniqueCore

final class OriginalConsolidationTests: XCTestCase {
    func testConsolidationPublishesVerifiedCopiesAndKeepsFailedReferences() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let first = try reference("Portrait.png", byte: 1, in: fixture.folder)
        let second = try reference("Scan.png", byte: 2, in: fixture.folder)
        let offline = try reference("Offline.png", byte: 3, in: fixture.folder)
        let conflict = try reference("Conflict.png", byte: 4, in: fixture.folder)
        let changed = try reference("Changed.png", byte: 5, in: fixture.folder)
        let excluded = try reference("Excluded.png", byte: 6, in: fixture.folder)
        try FileManager.default.removeItem(at: repo.originalURL(offline))
        try Data([55]).write(to: repo.originalURL(changed))
        let occupiedTarget = try repo.managedOriginalURL(conflict.filename)
        try Data([44]).write(to: occupiedTarget)
        var library = Library()
        library.photos = [first, second, offline, conflict, changed, excluded]
        let version = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        library.photos[6].trashedAt = Date()
        library.photos[6].adjustments.exposure = 0.35
        try repo.save(library)

        let report = try repo.consolidateOriginals([first.id, second.id, offline.id, conflict.id, changed.id], in: &library)

        XCTAssertEqual(report.consolidated, ["Portrait.png", "Scan.png"])
        XCTAssertEqual(report.unavailable, ["Offline.png"])
        XCTAssertEqual(report.occupied, ["Conflict.png"])
        XCTAssertEqual(report.failed, ["Changed.png"])
        let reopened = try LibraryRepository(root: repo.root).load()
        XCTAssertEqual(reopened.photos, library.photos)
        XCTAssertNil(reopened.photos[0].referencedPath)
        XCTAssertNil(reopened.photos[1].referencedPath)
        XCTAssertNil(reopened.photos[6].referencedPath)
        XCTAssertEqual(reopened.photos[6].id, version.id)
        XCTAssertEqual(reopened.photos[6].adjustments.exposure, 0.35)
        XCTAssertEqual(Array(reopened.photos[2...5]), [offline, conflict, changed, excluded])
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(reopened.photos[0])), Data([1]))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(reopened.photos[1])), Data([2]))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(first)), Data([1]))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(second)), Data([2]))
        XCTAssertEqual(try Data(contentsOf: occupiedTarget), Data([44]))
    }

    func testFailedCatalogueWriteCanRetryVerifiedCopies() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let original = try reference("Photo.png", byte: 11, in: fixture.folder)
        var library = Library()
        library.version = 2
        library.photos = [original]
        try repo.save(library)
        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        XCTAssertThrowsError(try repo.consolidateOriginals([original.id], in: &library))
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path)
        XCTAssertEqual(library.photos, [original])
        XCTAssertEqual(try Data(contentsOf: catalogue), before)

        let copy = try repo.managedOriginalURL(original.filename)
        let fileNumber = try FileManager.default.attributesOfItem(atPath: copy.path)[.systemFileNumber] as? NSNumber
        XCTAssertNotNil(fileNumber)
        XCTAssertEqual(try Data(contentsOf: copy), Data([11]))
        library = try repo.load()
        XCTAssertEqual(try repo.consolidateOriginals([original.id], in: &library).consolidated, ["Photo.png"])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: copy.path)[.systemFileNumber] as? NSNumber, fileNumber)
        XCTAssertNil(try repo.load().photos.first?.referencedPath)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(original)), Data([11]))
    }

    func testCancelledConsolidationKeepsOriginalReferenced() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let photo = try reference("Photo.png", byte: 15, in: fixture.folder)
        var library = Library()
        library.version = 2
        library.photos = [photo]
        try repo.save(library)
        let saved = library
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var draft = saved
            return try repo.consolidateOriginals([photo.id], in: &draft)
        }
        let report = try await task.value
        XCTAssertTrue(report.cancelled)
        XCTAssertTrue(report.consolidated.isEmpty)
        XCTAssertEqual(try repo.load().photos, [photo])
        XCTAssertFalse(FileManager.default.fileExists(atPath: try repo.managedOriginalURL(photo.filename).path))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(photo)), Data([15]))
    }

    private func fixture() throws -> (folder: URL, repo: LibraryRepository) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueConsolidation-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return (folder, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library")))
    }

    private func reference(_ name: String, byte: UInt8, in folder: URL) throws -> Photo {
        let source = folder.appendingPathComponent(name)
        try Data([byte]).write(to: source)
        var photo = Photo(filename: "managed-" + name, originalName: name, projectID: nil, width: 8, height: 8,
                          camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
        photo.referencedPath = source.path
        return photo
    }
}
