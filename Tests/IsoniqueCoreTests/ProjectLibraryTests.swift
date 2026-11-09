import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

final class ProjectLibraryTests: XCTestCase {
    func testProjectReopensIndependentlyWithEditsAndMemberships() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Collection(name: "Selected project")
        let otherProject = Collection(name: "Other project")
        let album = Collection(name: "Shared album")
        let otherAlbum = Collection(name: "Other album")
        var smart = Collection(name: "Highly rated")
        smart.rule = SmartAlbumRule(minimumRating: 4)
        var scoped = Collection(name: "Empty project Smart Album")
        scoped.rule = SmartAlbumRule(text: "No match")
        scoped.rule?.projectID = project.id
        var storage = Collection(name: "Referenced in source")
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .storage, comparison: .equals, value: "true")]
        storage.rule = SmartAlbumRule()
        storage.rule?.query = query

        let managedURL = try repository.managedOriginalURL("managed.png")
        let externalURL = folder.appendingPathComponent("external.png")
        try writePNG(to: managedURL, red: 0.3)
        try writePNG(to: externalURL, red: 0.7)
        var managed = try photo("managed.png", at: managedURL, project: project.id)
        managed.adjustments.exposure = 0.65
        managed.adjustments.quarterTurns = 1
        managed.caption = "Project caption"
        managed.rating = 5
        managed.albumIDs = [album.id, UUID()]
        managed.versions = [PhotoVersion(name: "Saved recipe", adjustments: managed.adjustments)]
        let stack = UUID(), splitStack = UUID(), pair = UUID()
        managed.stackID = stack
        managed.pairID = pair
        var external = try photo("reference.png", at: externalURL, project: otherProject.id)
        external.referencedPath = externalURL.path
        external.stackID = splitStack
        external.pairID = pair
        external.albumIDs = [album.id, otherAlbum.id]
        var trashed = Photo(filename: "trashed.png", originalName: "Trashed", projectID: project.id,
                            width: 8, height: 8, camera: "", captureDate: "", sha256: "offline")
        trashed.trashedAt = Date()
        var source = Library()
        source.projects = [project, otherProject]
        source.albums = [album, otherAlbum, smart, scoped, storage]
        source.photos = [managed, external, trashed]
        let version = try XCTUnwrap(source.createVersion(of: managed.id, from: .current))
        source.photos[3].adjustments.exposure = -0.5
        source.photos[3].pairID = UUID()
        let importedElsewhere = try XCTUnwrap(source.createVersion(of: external.id, from: .current))
        source.photos[4].projectID = project.id
        source.photos[4].albumIDs = [album.id]
        source.applyStackPick(StackPickChange(stackID: stack, photoID: managed.id, selectionID: managed.id))
        source.applyStackPick(StackPickChange(stackID: stack, albumID: album.id, photoID: version.id, selectionID: version.id))
        source.applyStackPick(StackPickChange(stackID: splitStack, photoID: external.id, selectionID: external.id))
        source.setStackCollapsed(true, stackID: stack)
        source.setStackCollapsed(true, stackID: splitStack)
        var history = EditHistory()
        history.record(managed)
        source.history = history
        try repository.save(source)

        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let sourceBytes = try Data(contentsOf: catalogue)
        let pixels = try Renderer.render(managedURL, adjustments: managed.adjustments)
        let destination = folder.appendingPathComponent("Exported")
        XCTAssertEqual(try LibraryBackup.exportProject(project.id, from: repository, to: destination), 3)
        XCTAssertEqual(try Data(contentsOf: catalogue), sourceBytes)
        XCTAssertEqual(try LibraryRepository.digest(managedURL), managed.sha256)
        XCTAssertEqual(try LibraryRepository.digest(externalURL), external.sha256)
        try FileManager.default.moveItem(at: externalURL, to: folder.appendingPathComponent("disconnected.png"))

        let (reopened, library) = try LibraryBackup.openVerified(destination)
        XCTAssertEqual(library.projects, [project])
        XCTAssertEqual(library.photos.map(\.id), [managed.id, version.id, importedElsewhere.id])
        XCTAssertEqual(library.albums.map(\.id), [album.id, smart.id, scoped.id, storage.id])
        XCTAssertEqual(library.albums[1].rule, smart.rule)
        XCTAssertEqual(library.albums[2].rule, scoped.rule)
        XCTAssertNil(library.albums[3].rule)
        XCTAssertEqual(library.photos[0].albumIDs, [album.id])
        XCTAssertEqual(library.photos[1].albumIDs, [album.id])
        XCTAssertEqual(library.photos[2].albumIDs, [album.id, storage.id])
        XCTAssertEqual(library.photos[0].adjustments, managed.adjustments)
        XCTAssertEqual(library.photos[0].versions, managed.versions)
        XCTAssertEqual(library.photos[1].adjustments.exposure, -0.5)
        XCTAssertEqual(library.photos[0].caption, managed.caption)
        XCTAssertNil(library.history)
        XCTAssertTrue(library.photos.allSatisfy { $0.projectID == project.id && $0.referencedPath == nil })
        XCTAssertEqual(library.photos[2].originalID, external.id)
        XCTAssertEqual(library.photos[0].pairID, pair)
        XCTAssertNil(library.photos[1].pairID)
        XCTAssertEqual(library.photos[2].pairID, pair)
        XCTAssertNil(library.photos[2].stackID)
        XCTAssertEqual(library.stackBrowser?.picks, [stack: managed.id])
        XCTAssertEqual(library.stackBrowser?.albumPicks, [album.id: [stack: version.id]])
        XCTAssertEqual(library.stackBrowser?.collapsed, [stack])
        XCTAssertEqual(try reopened.availableOriginalURL(library.photos[0]), try reopened.availableOriginalURL(library.photos[1]))
        XCTAssertEqual(try LibraryBackup.verify(reopened), 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: reopened.root.appendingPathComponent("Originals").path).count, 2)
        let restored = try Renderer.render(reopened.availableOriginalURL(library.photos[0]), adjustments: library.photos[0].adjustments)
        XCTAssertEqual(restored.width, pixels.width)
        XCTAssertEqual(restored.height, pixels.height)
        XCTAssertEqual(try XCTUnwrap(restored.dataProvider?.data) as Data, try XCTUnwrap(pixels.dataProvider?.data) as Data)
    }

    func testUnsafeOccupiedAndFailedCopiesLeaveNoPublishedLibrary() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Collection(name: "Project")
        let image = try repository.managedOriginalURL("photo.png")
        try Data([42]).write(to: image)
        var source = Library()
        source.projects = [project]
        source.photos = [try photo("photo.png", at: image, project: project.id)]
        try repository.save(source)

        let occupied = folder.appendingPathComponent("Occupied")
        try FileManager.default.createDirectory(at: occupied, withIntermediateDirectories: false)
        let sentinel = occupied.appendingPathComponent("sentinel")
        try Data([19]).write(to: sentinel)
        let dangling = folder.appendingPathComponent("Dangling")
        try FileManager.default.createSymbolicLink(at: dangling, withDestinationURL: folder.appendingPathComponent("Missing"))
        for target in [occupied, dangling, repository.root.appendingPathComponent("Nested")] {
            XCTAssertThrowsError(try LibraryBackup.exportProject(project.id, from: repository, to: target))
        }
        XCTAssertEqual(try Data(contentsOf: sentinel), Data([19]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Missing").path))

        let failed = folder.appendingPathComponent("Failed")
        try Data([1]).write(to: image)
        XCTAssertThrowsError(try LibraryBackup.exportProject(project.id, from: repository, to: failed))
        try FileManager.default.removeItem(at: image)
        XCTAssertThrowsError(try LibraryBackup.exportProject(project.id, from: repository, to: failed))
        XCTAssertFalse(FileManager.default.fileExists(atPath: failed.path))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".isonique-library-") })
    }

    func testCancellationAndConcurrentPublish() async throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Collection(name: "Empty project")
        var library = Library()
        library.projects = [project]
        try repository.save(library)
        let target = folder.appendingPathComponent("Destination")
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try LibraryBackup.exportProject(project.id, from: repository, to: target)
        }
        do {
            _ = try await cancelled.value
            XCTFail("Expected cancellation before publishing")
        } catch is CancellationError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let first = Task.detached { Result { try LibraryBackup.exportProject(project.id, from: repository, to: target) } }
        let second = Task.detached { Result { try LibraryBackup.exportProject(project.id, from: repository, to: target) } }
        let outcomes = await [first.value, second.value]
        XCTAssertEqual(outcomes.compactMap { try? $0.get() }, [0])
        let (_, reopened) = try LibraryBackup.openVerified(target)
        XCTAssertEqual(reopened.projects, [project])
        XCTAssertTrue(reopened.photos.isEmpty)
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: folder.path).contains { $0.hasPrefix(".isonique-library-") })
    }

    private func fixture() throws -> (URL, LibraryRepository) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueProjectLibrary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return (folder, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Source")))
    }

    private func photo(_ filename: String, at url: URL, project: UUID) throws -> Photo {
        Photo(filename: filename, originalName: url.lastPathComponent, projectID: project,
              width: 8, height: 6, camera: "", captureDate: "", sha256: try LibraryRepository.digest(url))
    }

    private func writePNG(to url: URL, red: CGFloat) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 6, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: red, green: 0.4, blue: 0.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 6))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }
}
