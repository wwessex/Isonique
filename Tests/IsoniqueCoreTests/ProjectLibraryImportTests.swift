import XCTest
@testable import IsoniqueCore

final class ProjectLibraryImportTests: XCTestCase {
    func testImportRemapsCollisionsAndPreservesIndependentMemberships() async throws {
        let (folder, destination) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Collection(name: "Shoot")
        let elsewhere = Collection(name: "Other")
        let album = Collection(name: "Picks")
        var smart = Collection(name: "Five stars")
        smart.rule = SmartAlbumRule(minimumRating: 5)
        var first = try photo("original.jpg", bytes: [1, 2], project: project.id, in: destination)
        var second = try photo("companion.nef", bytes: [3, 4], project: project.id, in: destination)
        var other = try photo("other.jpg", bytes: [5, 6], project: elsewhere.id, in: destination)
        let stackID = UUID(), pairID = UUID()
        first.albumIDs = [album.id]
        first.stackID = stackID
        first.pairID = pairID
        second.pairID = pairID
        first.adjustments.exposure = 0.5
        first.caption = "Keep this caption"
        first.rating = 5
        other.rating = 5
        let recipe = PhotoVersion(name: "Retained recipe", adjustments: first.adjustments)
        first.versions = [recipe]
        var library = Library()
        library.projects = [project, elsewhere]
        library.albums = [album, smart]
        library.photos = [first, second, other]
        let version = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        library.photos[3].adjustments.exposure = -0.3
        library.applyStackPick(StackPickChange(stackID: stackID, photoID: first.id, selectionID: first.id))
        library.applyStackPick(StackPickChange(stackID: stackID, albumID: album.id, photoID: version.id, selectionID: version.id))
        library.setStackCollapsed(true, stackID: stackID)
        var history = EditHistory()
        history.record(first)
        library.history = history
        try destination.save(library)
        let exported = folder.appendingPathComponent("Exported")
        try LibraryBackup.exportProject(project.id, from: destination, to: exported)
        let sourceCatalogue = exported.appendingPathComponent("catalog.json")
        let sourceBytes = try Data(contentsOf: sourceCatalogue)

        let result = try await destination.importProjectLibrary(from: exported)
        let (reopened, saved) = try LibraryBackup.openVerified(destination.root)
        XCTAssertEqual(result.photoCount, 3)
        XCTAssertEqual(result.project.name, "Shoot (2)")
        XCTAssertNotEqual(result.project.id, project.id)
        XCTAssertEqual(saved.projects, [project, elsewhere, result.project])
        XCTAssertEqual(Array(saved.photos.prefix(4)), library.photos)
        XCTAssertEqual(saved.history?.undo, history.undo)
        let imported = Array(saved.photos.dropFirst(4))
        XCTAssertEqual(imported.count, 3)
        XCTAssertTrue(Set(imported.map(\.id)).isDisjoint(with: library.photos.map(\.id)))
        XCTAssertEqual(imported.map(\.projectID), Array(repeating: result.project.id, count: 3))
        XCTAssertEqual(imported[2].originalID, imported[0].id)
        XCTAssertEqual(imported[0].filename, imported[2].filename)
        XCTAssertNotEqual(imported[0].filename, first.filename)
        XCTAssertEqual(imported[0].adjustments, first.adjustments)
        XCTAssertEqual(imported[0].caption, first.caption)
        XCTAssertEqual(imported[2].adjustments.exposure, -0.3)
        XCTAssertEqual(imported[0].versions?.first?.adjustments, recipe.adjustments)
        XCTAssertNotEqual(imported[0].versions?.first?.id, recipe.id)
        let importedStack = try XCTUnwrap(imported[0].stackID)
        let importedPair = try XCTUnwrap(imported[0].pairID)
        XCTAssertNotEqual(importedStack, stackID)
        XCTAssertNotEqual(importedPair, pairID)
        XCTAssertEqual(imported[2].stackID, importedStack)
        XCTAssertEqual(imported[1].pairID, importedPair)
        let newAlbum = saved.albums[2], newSmart = saved.albums[3]
        XCTAssertNotEqual(newAlbum.id, album.id)
        XCTAssertNotEqual(newSmart.id, smart.id)
        XCTAssertEqual(newAlbum.name, "Picks (2)")
        XCTAssertEqual(newSmart.name, "Five stars (2)")
        XCTAssertEqual(imported[0].albumIDs, [newAlbum.id])
        XCTAssertEqual(imported[2].albumIDs, [newAlbum.id])
        XCTAssertEqual(newSmart.rule?.projectID, result.project.id)
        XCTAssertTrue(newSmart.rule?.includes(imported[0]) == true)
        XCTAssertFalse(newSmart.rule?.includes(other) == true)
        XCTAssertEqual(saved.stackBrowser?.picks, [stackID: first.id, importedStack: imported[0].id])
        XCTAssertEqual(saved.stackBrowser?.albumPicks[newAlbum.id], [importedStack: imported[2].id])
        XCTAssertEqual(saved.stackBrowser?.collapsed, [stackID, importedStack])
        XCTAssertEqual(try LibraryBackup.verify(reopened), 5)
        XCTAssertEqual(try Data(contentsOf: sourceCatalogue), sourceBytes)

        let again = try await destination.importProjectLibrary(from: exported)
        XCTAssertEqual(again.project.name, "Shoot (3)")
        XCTAssertNotEqual(again.project.id, result.project.id)
        XCTAssertEqual(try LibraryBackup.verify(destination), 7)
    }

    func testPreservesNoncollidingIDsAndReservesOriginalIdentityFromUndoHistory() async throws {
        let (folder, destination) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Standalone"))
        let project = Collection(name: "Only a version")
        let original = try photo("original.png", bytes: [8], project: project.id, in: source)
        var version = original
        version.id = UUID()
        version.sharedOriginalID = original.id
        version.versionName = "Version 2"
        var exported = Library()
        exported.version = 3
        exported.projects = [project]
        exported.photos = [version]
        try source.save(exported)
        var undo = EditHistory()
        var previousOriginal = original
        previousOriginal.projectID = nil
        undo.record(previousOriginal)

        let imported = try await destination.importProjectLibrary(from: source.root, reserving: undo)
        let saved = try destination.load()
        XCTAssertEqual(imported.project.id, project.id)
        XCTAssertEqual(saved.photos.first?.id, version.id)
        XCTAssertNotEqual(saved.photos.first?.originalID, original.id)
        XCTAssertEqual(saved.photos.first?.versionName, version.versionName)
        XCTAssertEqual(try LibraryBackup.verify(destination), 1)
    }

    func testGlobalSmartAlbumFromVersionOneIsScopedAndReopens() async throws {
        let (folder, destination) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Legacy export"))
        let project = Collection(name: "Legacy")
        var smart = Collection(name: "All rated")
        smart.rule = SmartAlbumRule(minimumRating: 1)
        var library = Library()
        library.projects = [project]
        library.albums = [smart]
        var original = try photo("photo.jpg", bytes: [5], project: project.id, in: source)
        original.rating = 3
        library.photos = [original]
        try source.save(library)

        let imported = try await destination.importProjectLibrary(from: source.root)
        let (_, reopened) = try LibraryBackup.openVerified(destination.root)
        XCTAssertEqual(reopened.version, 2)
        XCTAssertEqual(reopened.albums.first?.rule?.projectID, imported.project.id)
        XCTAssertEqual(reopened.photos.first?.id, original.id)
        XCTAssertTrue(reopened.albums.first?.rule?.includes(try XCTUnwrap(reopened.photos.first)) == true)
    }

    func testCancellationAfterStagingAFileRollsBack() async throws {
        let (folder, destination) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try exportedFixture(in: folder)
        let catalogue = destination.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let job = Task.detached {
            try await destination.importProjectLibrary(from: source.root) { progress in
                if progress.processed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await job.value
            XCTFail("Expected cancellation after copying the first original")
        } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertTrue(try destination.load().projects.isEmpty)
        try assertNoImportedFiles(in: destination)
        XCTAssertEqual(try LibraryBackup.verify(source), 2)
    }

    func testFailedCatalogueSaveRollsBackPublishedOriginalsAndCanRetry() async throws {
        let (folder, destination) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try exportedFixture(in: folder)
        let catalogue = destination.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let files = FileManager.default
        try files.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? files.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        do {
            _ = try await destination.importProjectLibrary(from: source.root)
            XCTFail("Expected the catalogue write to fail")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        try assertNoImportedFiles(in: destination)
        try files.setAttributes([.immutable: false], ofItemAtPath: catalogue.path)

        let imported = try await destination.importProjectLibrary(from: source.root)
        XCTAssertEqual(imported.photoCount, 2)
        XCTAssertEqual(try LibraryBackup.verify(destination), 2)
        XCTAssertEqual(try LibraryBackup.verify(source), 2)
    }

    func testChangedDestinationAndCorruptSourceAbortWithoutPublishing() async throws {
        let (folder, destination) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = try exportedFixture(in: folder)
        let newProject = Collection(name: "New destination work")
        var updated = try destination.load()
        updated.projects.append(newProject)
        let replacement = updated
        do {
            _ = try await destination.importProjectLibrary(from: source.root) { progress in
                if progress.processed == 1 {
                    do { try destination.save(replacement) }
                    catch { XCTFail("Could not update destination during import: \(error)") }
                }
            }
            XCTFail("Expected a stale import to fail")
        } catch {}
        XCTAssertEqual(try destination.load().projects, [newProject])
        try assertNoImportedFiles(in: destination)

        try Data([99]).write(to: source.root.appendingPathComponent("Originals/second.png"))
        do {
            _ = try await destination.importProjectLibrary(from: source.root)
            XCTFail("Expected corrupt source bytes to fail verification")
        } catch {}
        XCTAssertEqual(try destination.load().projects, [newProject])
        try assertNoImportedFiles(in: destination)
    }

    private func fixture() throws -> (URL, LibraryRepository) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueProjectImport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return (folder, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Destination")))
    }

    private func exportedFixture(in folder: URL) throws -> LibraryRepository {
        let source = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Exported"))
        let project = Collection(name: "Project")
        var library = Library()
        library.projects = [project]
        library.photos = [
            try photo("first.png", bytes: [1], project: project.id, in: source),
            try photo("second.png", bytes: [2], project: project.id, in: source)
        ]
        try source.save(library)
        return source
    }

    private func photo(_ filename: String, bytes: [UInt8], project: UUID, in repository: LibraryRepository) throws -> Photo {
        let url = try repository.managedOriginalURL(filename)
        try Data(bytes).write(to: url)
        return Photo(filename: filename, originalName: filename, projectID: project,
                     width: 8, height: 6, camera: "", captureDate: "", sha256: try LibraryRepository.digest(url))
    }

    private func assertNoImportedFiles(in repository: LibraryRepository) throws {
        let files = FileManager.default
        XCTAssertTrue(try files.contentsOfDirectory(atPath: repository.root.appendingPathComponent("Originals").path).isEmpty)
        XCTAssertFalse(try files.contentsOfDirectory(atPath: repository.root.path).contains { $0.hasPrefix(".isonique-project-import-") })
    }
}
