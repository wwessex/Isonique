import XCTest
@testable import IsoniqueCore

final class OriginalReconnectTests: XCTestCase {
    func testReconnectVerifiesNamesAndBytesAndUpdatesSharedVersions() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let search = folder.appendingPathComponent("Search")
        let first = try write("Portrait.NEF", bytes: [1, 2], in: search.appendingPathComponent("Session A"))
        let second = try write("Scan.tiff", bytes: [3, 4], in: search.appendingPathComponent("Session B"))
        let ambiguous = try write("Duplicate.jpg", bytes: [5, 6], in: search.appendingPathComponent("Session A"))
        _ = try write("Duplicate.jpg", bytes: [5, 6], in: search.appendingPathComponent("Session B"))
        let wrong = try write("Wrong.jpg", bytes: [7, 8], in: folder)
        _ = try write("Wrong.jpg", bytes: [8, 7], in: search)
        let outside = try write("OnlyLink.jpg", bytes: [9, 10], in: folder)
        try FileManager.default.createSymbolicLink(at: search.appendingPathComponent("OnlyLink.jpg"), withDestinationURL: outside)
        let offline = folder.appendingPathComponent("Offline")
        let portrait = try referenced(first, name: "Renamed portrait.NEF", oldFolder: offline)
        let scan = try referenced(second, name: "Scan.tiff", oldFolder: offline)
        let duplicate = try referenced(ambiguous, name: "Duplicate.jpg", oldFolder: offline)
        let mismatch = try referenced(wrong, name: "Wrong.jpg", oldFolder: offline)
        let symlink = try referenced(outside, name: "OnlyLink.jpg", oldFolder: offline)
        var trashOnly = try referenced(second, name: "Trashed.tiff", oldFolder: offline)
        trashOnly.trashedAt = Date()
        var managed = try referenced(second, name: "Missing managed.tiff", oldFolder: offline)
        managed.referencedPath = nil
        var library = Library()
        library.photos = [portrait, scan, duplicate, mismatch, symlink, trashOnly, managed]
        let variant = try XCTUnwrap(library.createVersion(of: portrait.id, from: .current))
        library.photos[0].trashedAt = Date()
        library.photos[0].adjustments.exposure = 0.5
        try repo.save(library)

        let report = try repo.reconnectMissingReferences(in: search, library: &library)
        XCTAssertEqual(report.reconnected, ["Renamed portrait.NEF", "Scan.tiff"])
        XCTAssertEqual(report.ambiguous, ["Duplicate.jpg"])
        XCTAssertEqual(report.unmatched, ["Wrong.jpg", "OnlyLink.jpg"])
        XCTAssertEqual(report.scanErrors, 0)
        let reopened = try repo.load()
        XCTAssertEqual(reopened.photos, library.photos)
        XCTAssertEqual(reopened.photos.first { $0.id == variant.id }?.referencedPath, first.path)
        XCTAssertEqual(reopened.photos[0].referencedPath, first.path)
        XCTAssertEqual(reopened.photos[0].adjustments.exposure, 0.5)
        XCTAssertEqual(reopened.photos[1].referencedPath, second.path)
        XCTAssertEqual(Array(reopened.photos[2...6]), [duplicate, mismatch, symlink, trashOnly, managed])
        XCTAssertEqual(try Data(contentsOf: first), Data([1, 2]))
        XCTAssertEqual(try Data(contentsOf: second), Data([3, 4]))

        let secondPass = try repo.reconnectMissingReferences(in: search, library: &library)
        XCTAssertTrue(secondPass.reconnected.isEmpty)
        XCTAssertEqual(secondPass.ambiguous, ["Duplicate.jpg"])
        XCTAssertEqual(secondPass.unmatched, ["Wrong.jpg", "OnlyLink.jpg"])
    }

    func testSaveFailureDoesNotPublishPartialReconnect() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let search = folder.appendingPathComponent("Search")
        let file = try write("Photo.jpg", bytes: [1], in: search)
        let photo = try referenced(file, name: "Photo.jpg", oldFolder: folder.appendingPathComponent("Offline"))
        var library = Library()
        library.version = 2
        library.photos = [photo]
        try repo.save(library)
        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let backup = repo.root.appendingPathComponent("catalog.backup")
        try FileManager.default.moveItem(at: catalogue, to: backup)
        try FileManager.default.createDirectory(at: catalogue, withIntermediateDirectories: false)

        XCTAssertThrowsError(try repo.reconnectMissingReferences(in: search, library: &library))
        XCTAssertEqual(library.photos, [photo])
        XCTAssertEqual(try Data(contentsOf: file), Data([1]))
        try FileManager.default.removeItem(at: catalogue)
        try FileManager.default.moveItem(at: backup, to: catalogue)
        XCTAssertEqual(try repo.load().photos, [photo])
    }

    func testCancelledReconnectLeavesCatalogueUntouched() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let search = folder.appendingPathComponent("Search")
        let file = try write("Photo.jpg", bytes: [2], in: search)
        let photo = try referenced(file, name: "Photo.jpg", oldFolder: folder.appendingPathComponent("Offline"))
        var library = Library()
        library.version = 2
        library.photos = [photo]
        try repo.save(library)
        let initial = library
        let task = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var draft = initial
            XCTAssertThrowsError(try repo.reconnectMissingReferences(in: search, library: &draft)) {
                XCTAssertTrue($0 is CancellationError)
            }
            XCTAssertEqual(draft.photos, [photo])
        }
        try await task.value
        XCTAssertEqual(try repo.load().photos, [photo])
    }

    private func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueReconnect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    private func write(_ name: String, bytes: [UInt8], in folder: URL) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(name)
        try Data(bytes).write(to: url)
        return url
    }

    private func referenced(_ source: URL, name: String, oldFolder: URL) throws -> Photo {
        var photo = Photo(filename: "\(UUID().uuidString).jpg", originalName: name, projectID: nil, width: 8, height: 8,
                          camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
        photo.referencedPath = oldFolder.appendingPathComponent(source.lastPathComponent).path
        return photo
    }
}
