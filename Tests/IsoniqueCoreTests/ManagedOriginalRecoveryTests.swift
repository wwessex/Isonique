import XCTest
@testable import IsoniqueCore

final class ManagedOriginalRecoveryTests: XCTestCase {
    func testRecoversBackupNamesAndOriginalNamesWithoutWritingCatalogueOrSources() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let first = try photo("Portrait.nef", stored: "stored-portrait.nef", bytes: [1], in: fixture.search)
        let backup = try photo("Scan.tif", stored: "stored-scan.tif", bytes: [2], in: fixture.search,
                               backupName: "stored-scan.tif")
        let occupied = try photo("Occupied.jpg", stored: "occupied.jpg", bytes: [3], in: fixture.search)
        let wrong = try photo("Wrong.jpg", stored: "wrong.jpg", bytes: [4], in: fixture.search)
        try Data([40]).write(to: fixture.search.appendingPathComponent(wrong.originalName))
        let duplicate = try photo("Duplicate.jpg", stored: "duplicate.jpg", bytes: [5], in: fixture.search)
        let nested = fixture.search.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: false)
        try Data([5]).write(to: nested.appendingPathComponent(duplicate.originalName))
        var reference = try photo("Reference.jpg", stored: "reference.jpg", bytes: [6], in: fixture.search)
        reference.referencedPath = fixture.folder.appendingPathComponent("Offline/Reference.jpg").path
        let occupiedTarget = try repo.originalURL(occupied)
        try FileManager.default.createDirectory(at: occupiedTarget, withIntermediateDirectories: false)
        let marker = occupiedTarget.appendingPathComponent("keep")
        try Data([30]).write(to: marker)

        var library = Library()
        library.photos = [first, backup, occupied, wrong, duplicate, reference]
        let version = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        library.photos[0].adjustments.exposure = 0.4
        library.photos[1].trashedAt = Date()
        try repo.save(library)
        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)

        let report = try repo.recoverMissingManagedOriginals(in: fixture.search, library: library)

        XCTAssertEqual(report.restored, ["Portrait.nef", "Scan.tif"])
        XCTAssertEqual(report.occupied, ["Occupied.jpg"])
        XCTAssertEqual(report.unmatched, ["Wrong.jpg"])
        XCTAssertEqual(report.ambiguous, ["Duplicate.jpg"])
        XCTAssertTrue(report.failed.isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        let reopened = try LibraryRepository(root: repo.root).load()
        XCTAssertEqual(reopened.photos, library.photos)
        XCTAssertEqual(try repo.availableOriginalURL(version), try repo.availableOriginalURL(first))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(first)), Data([1]))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(backup)), Data([2]))
        XCTAssertEqual(try Data(contentsOf: fixture.search.appendingPathComponent("Portrait.nef")), Data([1]))
        XCTAssertEqual(try Data(contentsOf: fixture.search.appendingPathComponent("stored-scan.tif")), Data([2]))
        XCTAssertEqual(try Data(contentsOf: marker), Data([30]))
        XCTAssertThrowsError(try repo.availableOriginalURL(reference))
    }

    func testRetryAfterInterruptedStagingAndCompletedInstall() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let completed = try photo("Complete.jpg", stored: "complete.jpg", bytes: [1], in: fixture.search)
        let missing = try photo("Interrupted.jpg", stored: "interrupted.jpg", bytes: [2, 3], in: fixture.search)
        let occupied = try photo("Existing.jpg", stored: "existing.jpg", bytes: [4], in: fixture.search)
        let destination = try repo.originalURL(occupied)
        try Data([99]).write(to: destination)
        try Data([1]).write(to: repo.originalURL(completed))
        let orphan = repo.root.appendingPathComponent("Originals/.isonique-original-interrupted")
        try Data([2]).write(to: orphan)
        var library = Library()
        library.photos = [completed, missing, occupied]
        try repo.save(library)

        let reopened = try LibraryRepository(root: repo.root).load()
        let report = try repo.recoverMissingManagedOriginals(in: fixture.search, library: reopened)
        XCTAssertEqual(report.restored, ["Interrupted.jpg"])
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(missing)), Data([2, 3]))
        XCTAssertEqual(try Data(contentsOf: destination), Data([99]))
        XCTAssertEqual(try Data(contentsOf: orphan), Data([2]))
        XCTAssertTrue(try repo.recoverMissingManagedOriginals(in: fixture.search, library: reopened).restored.isEmpty)
    }

    func testCancelledScanAndCompetingInstallsPreserveFiles() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let bytes = Data(repeating: 83, count: 8 * 1024 * 1024)
        let source = fixture.search.appendingPathComponent("Photo.jpg")
        try bytes.write(to: source)
        let photo = Photo(filename: "managed.jpg", originalName: "Photo.jpg", projectID: nil, width: 8, height: 8,
                          camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
        var draft = Library()
        draft.photos = [photo]
        try repo.save(draft)
        let library = draft
        let search = fixture.search
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try repo.recoverMissingManagedOriginals(in: search, library: library)
        }
        do {
            _ = try await cancelled.value
            XCTFail("Expected cancellation before the scan")
        } catch is CancellationError {}
        XCTAssertThrowsError(try repo.availableOriginalURL(photo))

        let first = Task.detached { try repo.recoverMissingManagedOriginals(in: search, library: library) }
        let second = Task.detached { try repo.recoverMissingManagedOriginals(in: search, library: library) }
        let results = try await [first.value, second.value]
        XCTAssertEqual(results.flatMap(\.restored), ["Photo.jpg"])
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(photo)), bytes)
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        let managed = try FileManager.default.contentsOfDirectory(atPath: repo.root.appendingPathComponent("Originals").path)
        XCTAssertEqual(managed, ["managed.jpg"])
    }

    private func fixture() throws -> (folder: URL, search: URL, repo: LibraryRepository) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueManagedRecovery-\(UUID().uuidString)")
        let search = folder.appendingPathComponent("Search")
        try FileManager.default.createDirectory(at: search, withIntermediateDirectories: true)
        return (folder, search, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library")))
    }

    private func photo(_ name: String, stored: String, bytes: [UInt8], in folder: URL, backupName: String? = nil) throws -> Photo {
        let source = folder.appendingPathComponent(backupName ?? name)
        try Data(bytes).write(to: source)
        return Photo(filename: stored, originalName: name, projectID: nil, width: 8, height: 8,
                     camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
    }
}
