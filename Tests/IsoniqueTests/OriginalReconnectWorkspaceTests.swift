import XCTest
import IsoniqueCore
@testable import Isonique

final class OriginalReconnectWorkspaceTests: XCTestCase {
    @MainActor
    func testReconnectRefreshesUnavailableFilterAndKeepsCatalogueEdit() async throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueReconnectWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let workspace = Workspace(libraryRoot: repo.root)
        let original = folder.appendingPathComponent("Photo.jpg")
        try Data([1, 2, 3]).write(to: original)
        var photo = Photo(filename: "record.jpg", originalName: "Photo.jpg", projectID: nil, width: 8, height: 8,
                          camera: "", captureDate: "", sha256: try LibraryRepository.digest(original))
        photo.referencedPath = folder.appendingPathComponent("Moved/Photo.jpg").path
        photo.adjustments.exposure = 0.75
        var draft = workspace.library
        draft.version = 2
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.originalFilter = .unavailable
        workspace.selection = photo.id
        XCTAssertEqual(workspace.selected?.id, photo.id)
        let revision = workspace.originalStatusRevision

        await workspace.findOriginals(in: folder, operation: .reconnect)

        XCTAssertFalse(workspace.busy)
        XCTAssertNil(workspace.originalFolderTask)
        XCTAssertNil(workspace.error)
        XCTAssertEqual(workspace.originalFolderResult?.summary, "1 reconnected · 0 unmatched · 0 ambiguous")
        XCTAssertEqual(workspace.originalStatusRevision, revision + 1)
        XCTAssertTrue(workspace.photos.isEmpty)
        workspace.originalFilter = .all
        XCTAssertEqual(workspace.photos.first?.referencedPath, original.path)
        XCTAssertEqual(try repo.load().photos.first?.adjustments.exposure, 0.75)
        XCTAssertEqual(try Data(contentsOf: original), Data([1, 2, 3]))
    }

    @MainActor
    func testManagedRecoveryRefreshesUnavailableFilterAndReopensWithEdits() async throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueRecoveryWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let workspace = Workspace(libraryRoot: repo.root)
        let source = folder.appendingPathComponent("Photo.jpg")
        try Data([3, 2, 1]).write(to: source)
        var photo = Photo(filename: "record.jpg", originalName: "Photo.jpg", projectID: nil, width: 8, height: 8,
                          camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
        photo.adjustments.exposure = 0.75
        var draft = workspace.library
        draft.photos = [photo]
        XCTAssertTrue(workspace.commit(draft))
        workspace.originalFilter = .unavailable
        workspace.selection = photo.id
        let revision = workspace.originalStatusRevision

        await workspace.findOriginals(in: folder, operation: .recoverManaged)

        XCTAssertFalse(workspace.busy)
        XCTAssertNil(workspace.originalFolderTask)
        XCTAssertNil(workspace.error)
        XCTAssertEqual(workspace.originalFolderResult?.summary, "1 restored · 0 unmatched · 0 ambiguous")
        XCTAssertEqual(workspace.originalStatusRevision, revision + 1)
        XCTAssertTrue(workspace.photos.isEmpty)
        let reopened = Workspace(libraryRoot: repo.root)
        XCTAssertEqual(reopened.library.photos, [photo])
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(photo)), Data([3, 2, 1]))
    }

    @MainActor
    func testSelectedVersionsAndProjectLimitReconnect() async throws {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueScopedReconnect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repo = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let workspace = Workspace(libraryRoot: repo.root)
        let project = Collection(name: "Selected project")
        let otherProject = Collection(name: "Other project")
        func reference(_ name: String, project: Collection, byte: UInt8) throws -> Photo {
            let source = folder.appendingPathComponent(name)
            try Data([byte]).write(to: source)
            var photo = Photo(filename: UUID().uuidString + ".jpg", originalName: name, projectID: project.id,
                              width: 8, height: 8, camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
            photo.referencedPath = folder.appendingPathComponent("Offline").appendingPathComponent(name).path
            return photo
        }
        let shared = try reference("Shared.jpg", project: otherProject, byte: 1)
        let inProject = try reference("Project.jpg", project: project, byte: 2)
        let outside = try reference("Outside.jpg", project: otherProject, byte: 3)
        var draft = workspace.library
        draft.projects = [project, otherProject]
        draft.photos = [shared, inProject, outside]
        let version = try XCTUnwrap(draft.createVersion(of: shared.id, from: .current))
        draft.photos[3].projectID = project.id
        XCTAssertTrue(workspace.commit(draft))
        workspace.scope = "project:\(project.id)"
        workspace.batchMode = true
        workspace.batchSelection = [version.id, outside.id]

        let choices = workspace.originalFolderScopes(for: .reconnect)
        XCTAssertEqual(choices.map(\.title), ["Entire Library", "Selected Photos", "Current Project"])
        XCTAssertNil(choices[0].originalIDs)
        XCTAssertEqual(choices[1].originalIDs, [shared.id])
        XCTAssertEqual(choices[2].originalIDs, [shared.id, inProject.id])
        await workspace.findOriginals(in: folder, operation: .reconnect, originalIDs: choices[1].originalIDs)
        let afterSelection = try repo.load()
        let recoveredPath = folder.appendingPathComponent("Shared.jpg").path
        XCTAssertEqual(afterSelection.photos[0].referencedPath, recoveredPath)
        XCTAssertEqual(afterSelection.photos[3].referencedPath, recoveredPath)
        XCTAssertEqual(afterSelection.photos[1].referencedPath, inProject.referencedPath)
        XCTAssertEqual(afterSelection.photos[2].referencedPath, outside.referencedPath)

        await workspace.findOriginals(in: folder, operation: .reconnect, originalIDs: choices[2].originalIDs)
        let afterProject = try repo.load()
        XCTAssertEqual(afterProject.photos[1].referencedPath, folder.appendingPathComponent("Project.jpg").path)
        XCTAssertEqual(afterProject.photos[2].referencedPath, outside.referencedPath)
    }
}
