import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor
final class PeopleWorkflowTests: XCTestCase {
    func testUnnamedQueueHasStableOrderAndIncludesOnlyEligibleVersions() throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let project = IsoniqueCore.Collection(name: "First project")
        let other = IsoniqueCore.Collection(name: "Other project")
        let later = try queuePhoto("Later", id: 1, project: project.id, imported: 2)
        let shared = try queuePhoto("Shared", id: 3, project: project.id, imported: 1)
        var version = shared
        version.id = queueID(4)
        version.sharedOriginalID = shared.id
        version.versionName = "Alternate"
        var outside = try queuePhoto("Outside", id: 2, project: other.id, imported: 1)
        outside.people?.faces[0].assignName("Already named")
        var trashed = try queuePhoto("Trash", id: 5, project: project.id, imported: 0)
        trashed.trashedAt = Date()
        let unfiled = try queuePhoto("Unfiled", id: 6, project: nil, imported: 3)
        var draft = try repository.load()
        draft.projects = [project, other]
        draft.photos = [later, version, trashed, outside, unfiled, shared]
        _ = try repository.save(draft)

        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        model.search = "Nothing matches"
        XCTAssertTrue(model.photos.isEmpty)
        let scoped = model.unnamedFaces(in: .project(project.id))
        XCTAssertEqual(scoped.map { $0.photo.id }, [shared.id, shared.id, version.id, version.id, later.id, later.id])
        XCTAssertEqual(scoped.prefix(2).map { $0.face.id }, shared.people?.faces.map(\.id))
        XCTAssertEqual(scoped.map(\.number), [1, 2, 1, 2, 1, 2])
        XCTAssertEqual(Set(scoped.map(\.id)).count, 6, "Shared face IDs must be distinct queue entries across versions")
        XCTAssertEqual(model.unnamedFaces(in: .project(other.id)).map(\.number), [2])
        let all = model.unnamedFaces(in: .library)
        XCTAssertEqual(all.map { $0.photo.id }, [outside.id] + scoped.map { $0.photo.id } + [unfiled.id, unfiled.id])
        XCTAssertTrue(model.unnamedFaces(in: .project(UUID())).isEmpty)
        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.unnamedFaces(in: .library).map(\.id), all.map(\.id))
    }

    func testUnnamedQueueAdvancesOfflineAndRestoresDecisionsAfterRestart() throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let project = IsoniqueCore.Collection(name: "Review")
        var target = try queuePhoto("Offline", id: 1, project: project.id, imported: 1)
        target.referencedPath = folder.appendingPathComponent("Missing.png").path
        target.adjustments.exposure = 0.4
        let next = try queuePhoto("Next", id: 2, project: project.id, imported: 2)
        var named = try queuePhoto("Names", id: 3, project: nil, imported: 3)
        named.people?.faces[0].assignName("Zoë Rivera")
        var draft = try repository.load()
        draft.projects = [project]
        draft.photos = [target, next, named]
        _ = try repository.save(draft)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        let scope = UnnamedFaceScope.project(project.id)
        model.openUnnamedFaces(scope)
        let review = try XCTUnwrap(model.unnamedFaceReview)
        XCTAssertEqual(review.initialScope, scope)
        let first = try XCTUnwrap(model.unnamedFaces(in: scope).first)
        XCTAssertThrowsError(try repository.availableOriginalURL(first.photo))
        XCTAssertFalse(model.resolveUnnamedFace(first, in: scope, review: review, decision: .newName("  ")))
        XCTAssertFalse(model.resolveUnnamedFace(first, in: scope, review: review, decision: .existingName("missing")))
        XCTAssertEqual(model.unnamedFaces(in: scope).first?.id, first.id)
        XCTAssertFalse(model.canUndo)
        XCTAssertTrue(model.resolveUnnamedFace(first, in: scope, review: review, decision: .existingName("zoe rivera")))
        let second = try XCTUnwrap(model.unnamedFaces(in: scope).first)
        XCTAssertEqual(second.number, 2)
        XCTAssertFalse(model.resolveUnnamedFace(first, in: scope, review: review, decision: .dismiss))
        XCTAssertTrue(model.resolveUnnamedFace(second, in: scope, review: review, decision: .dismiss))
        let third = try XCTUnwrap(model.unnamedFaces(in: scope).first)
        XCTAssertEqual(third.photo.id, next.id)
        XCTAssertTrue(model.resolveUnnamedFace(third, in: scope, review: review, decision: .newName("  Sam   Lee  ")))
        XCTAssertEqual(model.unnamedFaces(in: scope).first?.number, 2)
        XCTAssertEqual(model.history.undo.count, 3)
        XCTAssertEqual(model.library.version, 37)

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.unnamedFaces(in: scope).count, 1)
        XCTAssertEqual(reopened.library.photos[0].personNames, ["Zoë Rivera"])
        XCTAssertEqual(reopened.library.photos[1].personNames, ["Sam Lee"])
        XCTAssertEqual(reopened.library.photos[0].adjustments, target.adjustments)
        var rescanned = try XCTUnwrap(reopened.library.photos[0].people)
        rescanned.incorporateDetections([second.face.region])
        XCTAssertEqual(rescanned.faces.map(\.id), [first.face.id])
        reopened.undoEdit()
        XCTAssertEqual(reopened.unnamedFaces(in: scope).first?.id, third.id)
        reopened.undoEdit()
        XCTAssertEqual(reopened.unnamedFaces(in: scope).first?.id, second.id)
        reopened.undoEdit()
        XCTAssertEqual(reopened.unnamedFaces(in: scope).first?.id, first.id)

        let redo = Workspace(libraryRoot: repository.root, preferences: preferences)
        redo.redoEdit()
        XCTAssertEqual(redo.unnamedFaces(in: scope).first?.id, second.id)
        redo.redoEdit()
        XCTAssertEqual(redo.unnamedFaces(in: scope).first?.id, third.id)
        redo.redoEdit()
        XCTAssertEqual(redo.unnamedFaces(in: scope).count, 1)
        XCTAssertEqual(redo.library.photos, model.library.photos)
    }

    func testUnnamedQueueDoesNotAdvanceWhenCatalogueSaveIsStale() throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        var draft = try repository.load()
        draft.photos = [try queuePhoto("Stale", id: 1, project: nil, imported: 1)]
        _ = try repository.save(draft)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        model.openUnnamedFaces(.library)
        let review = try XCTUnwrap(model.unnamedFaceReview)
        let first = try XCTUnwrap(model.unnamedFaces(in: .library).first)
        var newer = try repository.load()
        newer.photos[0].caption = "Saved elsewhere"
        _ = try repository.save(newer)
        XCTAssertFalse(model.resolveUnnamedFace(first, in: .library, review: review, decision: .dismiss))
        XCTAssertEqual(model.unnamedFaces(in: .library).first?.id, first.id)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(try repository.load().photos, newer.photos)
    }

    private func queueID(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    private func queuePhoto(_ name: String, id: Int, project: UUID?, imported: TimeInterval) throws -> Photo {
        var photo = Photo(filename: name + ".png", originalName: name + ".png", projectID: project,
                          width: 80, height: 60, camera: "", captureDate: "", sha256: name)
        photo.id = queueID(id)
        photo.importedAt = Date(timeIntervalSince1970: imported)
        photo.people = try detections()
        return photo
    }

    func testPeopleSurviveRestartAndWorkOfflineWithSearchAndSmartAlbums() throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let original = folder.appendingPathComponent("Group.png")
        try makeImage(original)
        var library = try repository.load()
        var options = ImportOptions()
        options.storage = .referenced
        XCTAssertTrue(try repository.importPhoto(original, projectID: nil, into: &library, options: options))
        let photoID = library.photos[0].id
        _ = try repository.save(library)
        let old = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertNil(old.library.photos[0].people)
        let review = PeopleReview(photo: old.library.photos[0], root: repository.root)

        var people = try detections()
        people.faces[0].assignName("Zoë Rivera")
        people.faces[1].assignName("Sam")
        XCTAssertTrue(old.applyPeopleReview(review, people: people))
        XCTAssertEqual(old.library.version, 37)
        XCTAssertEqual(old.peopleGroups.map(\.photoCount), [1, 1])
        XCTAssertEqual(old.history.undo.count, 1)
        XCTAssertFalse(old.applyPeopleReview(review, people: try detections()))
        old.error = nil

        let offline = folder.appendingPathComponent("Offline.png")
        try FileManager.default.moveItem(at: original, to: offline)
        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.library.photos[0].people, people)
        XCTAssertThrowsError(try repository.verifiedFaceSource(for: reopened.library.photos[0]))
        reopened.search = "zoe rivera"
        XCTAssertEqual(reopened.photos.map(\.id), [photoID])
        reopened.search = ""
        reopened.showFacePhotos()
        XCTAssertEqual(reopened.photos.map(\.id), [photoID])
        reopened.scope = try XCTUnwrap(reopened.peopleGroups.first { $0.name == "Zoë Rivera" }).scope
        XCTAssertEqual(reopened.photos.map(\.id), [photoID])

        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .person, comparison: .equals, value: "zoe rivera")]
        XCTAssertEqual(reopened.filteredPhotos(advancedQuery: query).map(\.id), [photoID])
        var rule = SmartAlbumRule()
        rule.query = query
        XCTAssertTrue(reopened.saveSmartAlbum(name: "Zoë", rule: rule))
        XCTAssertEqual(reopened.photos.map(\.id), [photoID])
        reopened.undoEdit()
        XCTAssertTrue(reopened.photos.isEmpty)
        XCTAssertNil(reopened.library.photos[0].people)
        reopened.redoEdit()
        XCTAssertEqual(reopened.photos.map(\.id), [photoID])

        var revised = people
        revised.faces[0].assignName("Different Person")
        revised.removeFace(revised.faces[1].id)
        let offlineReview = PeopleReview(photo: reopened.library.photos[0], root: repository.root)
        XCTAssertTrue(reopened.applyPeopleReview(offlineReview, people: revised))
        XCTAssertTrue(reopened.photos.isEmpty)
        reopened.undoEdit()
        XCTAssertEqual(reopened.photos.map(\.id), [photoID])
        XCTAssertEqual(reopened.library.photos[0].people, people)
        reopened.redoEdit()
        XCTAssertTrue(reopened.photos.isEmpty)
        let saved = try repository.load()
        XCTAssertEqual(saved.photos[0].people, revised)
        XCTAssertTrue(saved.albums[0].rule?.query?.criteria.first?.field == .person)
    }

    func testPeopleLeaveRecipesOriginalsAndAllPhotoExportsUnchanged() throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let original = folder.appendingPathComponent("Group.png")
        try makeImage(original)
        let digest = try LibraryRepository.digest(original)
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(original, projectID: nil, into: &library))
        library.photos[0].adjustments.exposure = 0.5
        library.photos[0].adjustments.quarterTurns = 1
        _ = try repository.save(library)
        let old = library.photos[0]
        let managed = try repository.availableOriginalURL(old)
        let before = try Renderer.render(managed, adjustments: old.adjustments)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        var people = try detections()
        people.faces[0].assignName("Unique Private Test Name")
        XCTAssertTrue(model.commitPeople([PhotoPeopleChange(photoID: old.id, people: people)]))
        let updated = model.library.photos[0]
        XCTAssertEqual(updated.adjustments, old.adjustments)
        let after = try Renderer.render(managed, adjustments: updated.adjustments)
        XCTAssertEqual(before.dataProvider?.data as Data?, after.dataProvider?.data as Data?)
        for format in [ExportFormat.png, .original] {
            var options = ExportOptions()
            options.format = format
            options.iptc = true
            options.xmpSidecar = true
            let stem = format == .original ? "original" : "edited"
            let first = folder.appendingPathComponent("before-\(stem).png")
            let second = folder.appendingPathComponent("after-\(stem).png")
            try Renderer.export(old, repository: repository, to: first, options: options)
            try Renderer.export(updated, repository: repository, to: second, options: options)
            XCTAssertEqual(try LibraryRepository.digest(first), try LibraryRepository.digest(second))
            let firstSidecar = try String(contentsOf: first.deletingPathExtension().appendingPathExtension("xmp"), encoding: .utf8)
            let secondSidecar = try String(contentsOf: second.deletingPathExtension().appendingPathExtension("xmp"), encoding: .utf8)
            XCTAssertEqual(firstSidecar, secondSidecar)
            XCTAssertFalse(secondSidecar.contains("Unique Private Test Name"))
        }
        XCTAssertEqual(try LibraryRepository.digest(original), digest)
        XCTAssertEqual(try LibraryRepository.digest(managed), digest)
    }

    func testSelectedScanSkipsHiddenPhotosAndCancellationDoesNotPublish() async throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let source = folder.appendingPathComponent("Visible.png")
        try makeImage(source)
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        let selectedID = library.photos[0].id
        let hidden = try XCTUnwrap(library.createVersion(of: selectedID, from: .current))
        library.photos[0].caption = "Only target"
        _ = try repository.save(library)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        model.batchMode = true
        model.batchSelection = [selectedID, hidden.id]
        model.search = "Only target"

        model.scanSelectedFaces()
        let cancelled = try XCTUnwrap(model.peopleScan)
        cancelled.cancel()
        _ = await cancelled.result
        try await waitForScan(model)
        XCTAssertEqual(model.status, "Face detection cancelled")
        XCTAssertTrue(try repository.load().photos.allSatisfy { $0.people == nil })

        model.scanSelectedFaces()
        let task = try XCTUnwrap(model.peopleScan)
        let result = try await task.value
        XCTAssertEqual(result.scanned, 1)
        try await waitForScan(model)
        let saved = try repository.load()
        XCTAssertTrue(saved.photos[0].people?.scanned == true)
        XCTAssertNil(saved.photos[1].people)
        XCTAssertEqual(model.history.undo.count, 1)
        model.undoEdit()
        XCTAssertTrue(try repository.load().photos.allSatisfy { $0.people == nil })
    }

    private func waitForScan(_ model: Workspace) async throws {
        for _ in 0..<100 where model.peopleScan != nil {
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNil(model.peopleScan)
    }

    private func fixture() throws -> (URL, LibraryRepository, UserDefaults, String) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniquePeople-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let suite = "IsoniquePeople.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        preferences.set(true, forKey: "history.persist")
        return (folder, repository, preferences, suite)
    }

    private func detections() throws -> PhotoPeople {
        var people = PhotoPeople()
        let left = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.35)))
        let right = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.6, y: 0.2, width: 0.25, height: 0.35)))
        people.incorporateDetections([left, right])
        return people
    }

    private func makeImage(_ url: URL) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: 96, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: 0.7, green: 0.3, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
        let image = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
