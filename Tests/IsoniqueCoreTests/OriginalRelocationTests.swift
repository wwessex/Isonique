import XCTest
@testable import IsoniqueCore

final class OriginalRelocationTests: XCTestCase {
    func testRelocationSavesAllVersionsBeforeRemovingManagedCopies() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let first = try managed("Portrait.png", filename: "first.png", bytes: [1], in: repo)
        let second = try managed("Portrait.png", filename: "second.png", bytes: [2], in: repo)
        let occupied = try managed("Occupied.png", filename: "third.png", bytes: [3], in: repo)
        let unrelated = try managed("Unrelated.png", filename: "fourth.png", bytes: [4], in: repo)
        try Data([9]).write(to: fixture.target.appendingPathComponent("Occupied.png"))
        try FileManager.default.createDirectory(at: fixture.target.appendingPathComponent("third.png"),
                                                withIntermediateDirectories: false)
        var library = Library()
        library.photos = [first, second, occupied, unrelated]
        let version = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        library.photos[4].trashedAt = Date()
        library.photos[4].adjustments.exposure = 0.6
        try repo.save(library)

        var released: [String] = []
        let report = try repo.relocateManagedOriginals([first.id, second.id, occupied.id], to: fixture.target, in: &library) { source in
            let saved = try repo.load()
            XCTAssertNotNil(saved.photos[0].referencedPath)
            XCTAssertEqual(saved.photos[0].referencedPath, saved.photos[4].referencedPath)
            XCTAssertNotNil(saved.photos[1].referencedPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            try FileManager.default.moveItem(at: source, to: fixture.trash.appendingPathComponent(source.lastPathComponent))
            released.append(source.lastPathComponent)
        }

        XCTAssertEqual(report.relocated, ["Portrait.png", "Portrait.png"])
        XCTAssertEqual(report.renamed, ["second.png"])
        XCTAssertEqual(report.occupied, ["Occupied.png"])
        XCTAssertTrue(report.retained.isEmpty)
        XCTAssertEqual(released, ["first.png", "second.png"])
        let saved = try LibraryRepository(root: repo.root).load()
        XCTAssertEqual(saved.photos, library.photos)
        XCTAssertEqual(saved.photos[4].id, version.id)
        XCTAssertEqual(saved.photos[4].adjustments.exposure, 0.6)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(saved.photos[4])), Data([1]))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(saved.photos[1])), Data([2]))
        XCTAssertEqual(try Data(contentsOf: fixture.target.appendingPathComponent("Occupied.png")), Data([9]))
        XCTAssertNil(saved.photos[2].referencedPath)
        XCTAssertNil(saved.photos[3].referencedPath)
        XCTAssertEqual(try LibraryBackup.verify(repo), 4)
    }

    func testFailedSaveKeepsManagedOriginalAndRetryReusesExactDestination() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let photo = try managed("Photo.png", filename: "storage.png", bytes: [7], in: repo)
        var library = Library()
        library.photos = [photo]
        try repo.save(library)
        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        XCTAssertThrowsError(try repo.relocateManagedOriginals([photo.id], to: fixture.target, in: &library) { _ in
            XCTFail("An unsaved relocation must never release the source")
        })
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertEqual(library.photos, [photo])
        let managedPath = try repo.availableOriginalURL(photo)
        XCTAssertEqual(try Data(contentsOf: managedPath), Data([7]))
        let destination = fixture.target.appendingPathComponent("Photo.png")
        let fileID = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber)

        let report = try repo.relocateManagedOriginals([photo.id], to: fixture.target, in: &library) { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(report.relocated, ["Photo.png"])
        XCTAssertEqual(report.retained, ["Photo.png"])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber, fileID)
        let saved = try repo.load()
        XCTAssertEqual(saved.version, 2)
        XCTAssertNotNil(saved.photos[0].referencedPath)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(saved.photos[0])), Data([7]))
        XCTAssertEqual(try Data(contentsOf: managedPath), Data([7]))
    }

    func testCancellationAndUnsafeDestinationPreserveManagedOriginal() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let photo = try managed("Photo.png", filename: "storage.png", bytes: [8], in: repo)
        var library = Library()
        library.photos = [photo]
        try repo.save(library)
        let inside = repo.root.appendingPathComponent("Originals")
        XCTAssertThrowsError(try repo.relocateManagedOriginals([photo.id], to: inside, in: &library) { _ in XCTFail() })
        let saved = library
        let target = fixture.target
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var draft = saved
            return try repo.relocateManagedOriginals([photo.id], to: target, in: &draft) { _ in XCTFail() }
        }
        do {
            _ = try await cancelled.value
            XCTFail("Expected cancellation before copying")
        } catch is CancellationError {}
        XCTAssertEqual(try repo.load().photos, [photo])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(photo)), Data([8]))
    }

    private func fixture() throws -> (folder: URL, repo: LibraryRepository, target: URL, trash: URL) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueRelocation-\(UUID().uuidString)")
        let target = folder.appendingPathComponent("Destination")
        let trash = folder.appendingPathComponent("Test Trash")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        return (folder, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library")), target, trash)
    }

    private func managed(_ name: String, filename: String, bytes: [UInt8], in repo: LibraryRepository) throws -> Photo {
        let source = try repo.managedOriginalURL(filename)
        try Data(bytes).write(to: source)
        return Photo(filename: filename, originalName: name, projectID: nil, width: 8, height: 8,
                     camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
    }
}
