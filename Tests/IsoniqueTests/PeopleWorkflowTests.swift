import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor
final class PeopleWorkflowTests: XCTestCase {
    func testReviewSummaryCountsVersionsFacesAndDistinctOfflineOriginalsByScope() async throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let project = IsoniqueCore.Collection(name: "Review")
        let other = IsoniqueCore.Collection(name: "Other project")
        let source = folder.appendingPathComponent("Referenced.png")
        try makeImage(source)
        var options = ImportOptions()
        options.storage = .referenced
        var draft = try repository.load()
        draft.projects = [project, other]
        XCTAssertTrue(try repository.importPhoto(source, projectID: project.id, into: &draft, options: options))
        let reference = draft.photos[0]
        var otherVersion = try XCTUnwrap(draft.createVersion(of: reference.id, from: .current))
        otherVersion.projectID = other.id
        draft.photos[1] = otherVersion

        var missing = try queuePhoto("Missing managed", id: 1, project: project.id, imported: 1)
        missing.people?.faces[0].assignName("Sam")
        var unscannedVersion = missing
        unscannedVersion.id = queueID(2)
        unscannedVersion.sharedOriginalID = missing.id
        unscannedVersion.people = nil
        var trashed = try queuePhoto("Trash", id: 3, project: project.id, imported: 2)
        trashed.trashedAt = Date()
        let unfiled = try queuePhoto("Unfiled", id: 4, project: nil, imported: 3)
        draft.photos += [missing, unscannedVersion, trashed, unfiled]
        let saved = try repository.save(draft)

        let scoped = PeopleReviewSummary(library: saved, scope: .project(project.id))
        let offlineInProject = try await scoped.offlineOriginals(in: repository)
        XCTAssertEqual(Set(scoped.unscannedVersions.map(\.id)), [reference.id, unscannedVersion.id])
        XCTAssertEqual(scoped.unnamedFaceCount, 1)
        XCTAssertEqual(offlineInProject.managed.map(\.originalID), [missing.id])
        XCTAssertTrue(offlineInProject.referenced.isEmpty)
        XCTAssertNil(offlineInProject.reconnectAction)
        XCTAssertEqual(offlineInProject.count, 1)
        XCTAssertEqual(scoped.availableVersionCount(offlineOriginals: offlineInProject.originalIDs), 1)

        let parked = folder.appendingPathComponent("Disconnected.png")
        try FileManager.default.moveItem(at: source, to: parked)
        let all = PeopleReviewSummary(library: saved, scope: .library)
        let offlineInLibrary = try await all.offlineOriginals(in: repository)
        XCTAssertEqual(Set(all.unscannedVersions.map(\.id)), [reference.id, otherVersion.id, unscannedVersion.id])
        XCTAssertEqual(all.unnamedFaceCount, 3)
        XCTAssertEqual(offlineInLibrary.managed.map(\.originalID), [missing.id, unfiled.id])
        XCTAssertEqual(offlineInLibrary.referenced.map(\.originalID), [reference.id])
        XCTAssertEqual(offlineInLibrary.reconnectAction, .reconnect([reference.id]))
        XCTAssertEqual(offlineInLibrary.count, 3)
        XCTAssertEqual(all.availableVersionCount(offlineOriginals: offlineInLibrary.originalIDs), 0)
        let otherSummary = PeopleReviewSummary(library: saved, scope: .project(other.id))
        let otherOffline = try await otherSummary.offlineOriginals(in: repository)
        XCTAssertEqual(otherSummary.unscannedVersions.map(\.id), [otherVersion.id])
        XCTAssertTrue(otherOffline.managed.isEmpty)
        XCTAssertEqual(otherOffline.referenced.map(\.originalID), [reference.id])

        try FileManager.default.moveItem(at: parked, to: source)
        let reconnected = try await all.offlineOriginals(in: repository)
        XCTAssertEqual(reconnected.managed.map(\.originalID), [missing.id, unfiled.id])
        XCTAssertTrue(reconnected.referenced.isEmpty)
        XCTAssertEqual(all.availableVersionCount(offlineOriginals: reconnected.originalIDs), 2)
        let empty = PeopleReviewSummary(library: saved, scope: .project(UUID()))
        let emptyOffline = try await empty.offlineOriginals(in: repository)
        XCTAssertTrue(empty.unscannedVersions.isEmpty)
        XCTAssertEqual(empty.unnamedFaceCount, 0)
        XCTAssertEqual(emptyOffline.count, 0)
        XCTAssertTrue(try repository.load().hasSameCatalogueRevision(as: saved))
    }

    func testOfflineListIsReadOnlyAndLimitedReconnectRefreshesSharedVersions() async throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let project = IsoniqueCore.Collection(name: "Review")
        let other = IsoniqueCore.Collection(name: "Other")
        let sources = folder.appendingPathComponent("Sources")
        let moved = folder.appendingPathComponent("Moved")
        for directory in [sources, moved] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        }
        let first = sources.appendingPathComponent("First.png")
        let second = sources.appendingPathComponent("Second.png")
        try makeImage(first)
        try makeImage(second, red: 0.1)
        var draft = try repository.load()
        draft.projects = [project, other]
        var options = ImportOptions()
        options.storage = .referenced
        XCTAssertTrue(try repository.importPhoto(first, projectID: project.id, into: &draft, options: options))
        XCTAssertTrue(try repository.importPhoto(second, projectID: other.id, into: &draft, options: options))
        let firstID = draft.photos[0].id
        let secondID = draft.photos[1].id
        let version = try XCTUnwrap(draft.createVersion(of: firstID, from: .current))
        draft.photos[2].projectID = other.id
        _ = try repository.save(draft)
        let movedFirst = moved.appendingPathComponent(first.lastPathComponent)
        try FileManager.default.moveItem(at: first, to: movedFirst)
        try FileManager.default.moveItem(at: second, to: moved.appendingPathComponent(second.lastPathComponent))

        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let fileManager = FileManager.default
        let beforeAttributes = try fileManager.attributesOfItem(atPath: catalogue.path)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        let scope = UnnamedFaceScope.project(project.id)
        model.openPeopleSummary(scope)
        let summary = PeopleReviewSummary(library: model.library, scope: scope)
        let offline = try await summary.offlineOriginals(in: repository)
        guard case .reconnect(let targetIDs)? = offline.reconnectAction else { return XCTFail("Missing scoped reconnect") }
        XCTAssertEqual(targetIDs, [firstID])
        XCTAssertEqual(offline.referenced.map(\.referencedPath), [first.path])
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        let afterAttributes = try fileManager.attributesOfItem(atPath: catalogue.path)
        XCTAssertEqual(afterAttributes[.systemFileNumber] as? NSNumber, beforeAttributes[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(afterAttributes[.modificationDate] as? Date, beforeAttributes[.modificationDate] as? Date)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.originalStatusRevision, 0)

        model.continueFromPeopleSummary(.reconnect(targetIDs))
        XCTAssertNil(model.peopleSummary)
        XCTAssertEqual(model.pendingPeopleSummaryAction?.root, repository.root)
        XCTAssertEqual(model.pendingPeopleSummaryAction?.action, .reconnect(targetIDs))
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        await model.findOriginals(in: moved, operation: .reconnect, originalIDs: targetIDs)
        XCTAssertEqual(model.originalStatusRevision, 1)
        XCTAssertEqual(try repository.load().photos.filter { $0.originalID == firstID }.map(\.referencedPath),
                       [movedFirst.path, movedFirst.path])
        XCTAssertEqual(model.library.photos.first { $0.id == version.id }?.referencedPath, movedFirst.path)
        XCTAssertEqual(model.library.photos.first { $0.id == secondID }?.referencedPath, second.path)

        let refreshedProject = try await PeopleReviewSummary(library: model.library, scope: scope).offlineOriginals(in: repository)
        let refreshedLibrary = try await PeopleReviewSummary(library: model.library, scope: .library).offlineOriginals(in: repository)
        XCTAssertEqual(refreshedProject.count, 0)
        XCTAssertEqual(refreshedLibrary.referenced.map(\.originalID), [secondID])
    }

    func testReviewSummaryActionsScanAvailableVersionsAndOpenScopedOfflineQueue() async throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let project = IsoniqueCore.Collection(name: "Review")
        let other = IsoniqueCore.Collection(name: "Other project")
        let source = folder.appendingPathComponent("Available.png")
        try makeImage(source)
        var draft = try repository.load()
        draft.projects = [project, other]
        XCTAssertTrue(try repository.importPhoto(source, projectID: project.id, into: &draft))
        let available = draft.photos[0]
        var outside = try XCTUnwrap(draft.createVersion(of: available.id, from: .current))
        outside.projectID = other.id
        draft.photos[1] = outside
        var alreadyScanned = try XCTUnwrap(draft.createVersion(of: available.id, from: .current))
        alreadyScanned.people = PhotoPeople()
        alreadyScanned.people?.incorporateDetections([])
        draft.photos[2] = alreadyScanned
        var offline = try queuePhoto("Offline", id: 1, project: project.id, imported: 1)
        let face = try XCTUnwrap(offline.people?.faces.first)
        offline.people = PhotoPeople()
        offline.people?.faces = [face]
        draft.photos.append(offline)
        _ = try repository.save(draft)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        model.scope = "project:\(project.id.uuidString)"
        model.search = "Nothing matches"
        XCTAssertTrue(model.photos.isEmpty)
        let scope = UnnamedFaceScope.project(project.id)
        XCTAssertEqual(model.currentPeopleReviewScope, scope)
        model.openPeopleSummary(model.currentPeopleReviewScope)
        XCTAssertEqual(model.peopleSummary?.initialScope, scope)

        model.scanUnscannedFaces(in: scope)
        let task = try XCTUnwrap(model.peopleScan?.task)
        let result = try await task.value
        try await waitForScan(model)
        XCTAssertEqual(result.scanned, 1)
        XCTAssertEqual(result.skippedVersions, [PeopleScanSkip(photo: offline, reason: .unavailable)])
        XCTAssertEqual(model.status, "Checked 1 photo version for faces · 1 version skipped")
        XCTAssertEqual(result.changes.map(\.photoID), [available.id])
        XCTAssertEqual(model.history.undo.count, 1)
        let saved = try repository.load()
        XCTAssertTrue(saved.photos[0].people?.scanned == true)
        XCTAssertNil(saved.photos[1].people)
        XCTAssertEqual(saved.photos[2], alreadyScanned)
        let summary = PeopleReviewSummary(library: saved, scope: scope)
        XCTAssertEqual(summary.unscannedVersions.map(\.id), [offline.id])
        XCTAssertEqual(summary.unnamedFaceCount, 1)

        model.continueFromPeopleSummary(.review(scope))
        XCTAssertNil(model.peopleSummary)
        XCTAssertNil(model.unnamedFaceReview)
        model.finishPeopleSummary()
        let review = try XCTUnwrap(model.unnamedFaceReview)
        XCTAssertEqual(review.initialScope, scope)
        let target = try XCTUnwrap(model.unnamedFaces(in: scope).first)
        XCTAssertEqual(target.photo.id, offline.id)
        XCTAssertTrue(model.resolveUnnamedFace(target, in: scope, review: review, decision: .newName("Alex")))
        XCTAssertEqual(PeopleReviewSummary(library: model.library, scope: scope).unnamedFaceCount, 0)
        model.undoEdit()
        XCTAssertEqual(PeopleReviewSummary(library: model.library, scope: scope).unnamedFaceCount, 1)
    }

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
        let cancelled = try XCTUnwrap(model.peopleScan?.task)
        cancelled.cancel()
        _ = await cancelled.result
        try await waitForScan(model)
        XCTAssertEqual(model.status, "Face detection cancelled")
        XCTAssertTrue(try repository.load().photos.allSatisfy { $0.people == nil })

        model.scanSelectedFaces()
        let task = try XCTUnwrap(model.peopleScan?.task)
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

    func testScanProgressSkipsAnOriginalDisconnectedMidScanAndSavesOneUndoStep() async throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let offline = folder.appendingPathComponent("Disconnect.png")
        let corrupt = folder.appendingPathComponent("Changed.png")
        let first = folder.appendingPathComponent("First.png")
        let last = folder.appendingPathComponent("Last.png")
        try makeImage(first)
        try makeImage(offline, red: 0.2)
        try makeImage(corrupt, red: 0.4)
        try makeImage(last, width: 128)
        var library = try repository.load()
        var options = ImportOptions()
        options.storage = .referenced
        for url in [first, offline, corrupt, last] {
            XCTAssertTrue(try repository.importPhoto(url, projectID: nil, into: &library, options: options))
        }
        let saved = try repository.save(library)
        try makeImage(corrupt, red: 0.6)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        let started = expectation(description: "First original reached detection")
        let finishing = expectation(description: "Last original reached detection")
        let firstGate = AsyncStream<Void>.makeStream()
        let lastGate = AsyncStream<Void>.makeStream()
        defer { firstGate.continuation.finish(); lastGate.continuation.finish() }

        model.scanFaces(saved.photos) { image in
            if image.width == 96 {
                started.fulfill()
                for await _ in firstGate.stream {}
            } else {
                finishing.fulfill()
                for await _ in lastGate.stream {}
            }
            return []
        }
        let job = try XCTUnwrap(model.peopleScan)
        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(job.progress.counts, PeopleScanCounts(total: 4))
        XCTAssertEqual(job.progress.counts.remaining, 4)
        try FileManager.default.moveItem(at: offline, to: folder.appendingPathComponent("Disconnected.png"))
        firstGate.continuation.finish()

        await fulfillment(of: [finishing], timeout: 5)
        XCTAssertEqual(job.progress.counts, PeopleScanCounts(total: 4, checked: 1, skipped: 2))
        XCTAssertEqual(job.progress.counts.remaining, 1)
        XCTAssertTrue(try repository.load().hasSameCatalogueRevision(as: saved))
        lastGate.continuation.finish()

        let result = try await job.task.value
        try await waitForScan(model)
        XCTAssertEqual(job.progress.counts, PeopleScanCounts(total: 4, checked: 2, skipped: 2))
        XCTAssertEqual(job.progress.counts.remaining, 0)
        XCTAssertEqual(result.skippedVersions, [
            PeopleScanSkip(photo: saved.photos[1], reason: .unavailable),
            PeopleScanSkip(photo: saved.photos[2], reason: .processingFailed(
                LibraryError.integrity(corrupt.lastPathComponent).localizedDescription))
        ])
        XCTAssertEqual(model.peopleScanReport?.skippedVersions, result.skippedVersions)
        XCTAssertNil(model.error)
        XCTAssertEqual(try repository.load().photos.map { $0.people?.scanned }, [true, nil, nil, true])
        XCTAssertEqual(model.history.undo.count, 1)
        model.undoEdit()
        XCTAssertEqual(try repository.load().photos, saved.photos)
        XCTAssertFalse(model.canUndo)
    }

    func testCancellingAfterProgressDiscardsCompletedChecks() async throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let first = folder.appendingPathComponent("First.png")
        let second = folder.appendingPathComponent("Second.png")
        try makeImage(first)
        try makeImage(second, width: 128)
        var library = try repository.load()
        for url in [first, second] {
            XCTAssertTrue(try repository.importPhoto(url, projectID: nil, into: &library))
        }
        let saved = try repository.save(library)
        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        let started = expectation(description: "Second original reached detection")
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        let face = try XCTUnwrap(FaceRegion(imageRect: CGRect(x: 0.1, y: 0.2, width: 0.25, height: 0.35)))

        model.scanFaces(saved.photos) { image in
            if image.width == 128 {
                started.fulfill()
                for await _ in gate.stream {}
            }
            return [face]
        }
        let job = try XCTUnwrap(model.peopleScan)
        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(job.progress.counts, PeopleScanCounts(total: 2, checked: 1))
        XCTAssertEqual(job.progress.counts.remaining, 1)
        job.progress.cancel(job.task)
        XCTAssertTrue(job.progress.isCancelling)
        do {
            _ = try await job.task.value
            XCTFail("The cancelled scan returned results")
        } catch is CancellationError {}
        try await waitForScan(model)
        XCTAssertEqual(job.progress.counts, PeopleScanCounts(total: 2, checked: 1))
        XCTAssertEqual(model.status, "Face detection cancelled")
        XCTAssertFalse(model.busy)
        XCTAssertFalse(model.canUndo)
        XCTAssertEqual(model.library.photos, saved.photos)
        XCTAssertTrue(try repository.load().hasSameCatalogueRevision(as: saved))
    }

    func testSkippedReportRetainsEachVersionAndRetriesOnlyItsBatchAfterReconnect() async throws {
        let (folder, repository, preferences, suite) = try fixture()
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let project = IsoniqueCore.Collection(name: "Batch")
        let other = IsoniqueCore.Collection(name: "Other Project")
        let available = folder.appendingPathComponent("Available.png")
        let shared = folder.appendingPathComponent("Offline.png")
        let second = folder.appendingPathComponent("Second Offline.png")
        let outside = folder.appendingPathComponent("Outside.png")
        try makeImage(available)
        try makeImage(shared, red: 0.2)
        try makeImage(second, red: 0.4, width: 128)
        try makeImage(outside, red: 0.6)
        var draft = try repository.load()
        draft.projects = [project, other]
        var options = ImportOptions()
        options.storage = .referenced
        for source in [available, shared, second, outside] {
            let projectID = source == outside ? other.id : project.id
            XCTAssertTrue(try repository.importPhoto(source, projectID: projectID, into: &draft, options: options))
        }
        let firstVersion = draft.photos[1]
        let secondVersion = draft.photos[2]
        let outsideVersion = draft.photos[3]
        let trashedLater = try XCTUnwrap(draft.createVersion(of: firstVersion.id, from: .current))
        let scannedLater = try XCTUnwrap(draft.createVersion(of: firstVersion.id, from: .current))
        let outsideShared = try XCTUnwrap(draft.createVersion(of: firstVersion.id, from: .current))
        draft.photos[6].projectID = other.id
        _ = try repository.save(draft)
        let relocated = folder.appendingPathComponent("Relocated")
        try FileManager.default.createDirectory(at: relocated, withIntermediateDirectories: false)
        for source in [shared, second] {
            try FileManager.default.moveItem(at: source, to: relocated.appendingPathComponent(source.lastPathComponent))
        }

        let model = Workspace(libraryRoot: repository.root, preferences: preferences)
        model.scanUnscannedFaces(in: .project(project.id))
        let initial = try XCTUnwrap(model.peopleScan?.task)
        _ = try await initial.value
        try await waitForScan(model)
        let report = try XCTUnwrap(model.peopleScanReport)
        XCTAssertEqual(report.checked, 1)
        XCTAssertEqual(report.skippedVersions.map(\.id), [firstVersion.id, secondVersion.id, trashedLater.id, scannedLater.id])
        XCTAssertEqual(report.skippedVersions.map(\.reason), Array(repeating: .unavailable, count: 4))
        XCTAssertEqual(Set(report.skippedVersions.map(\.name)).count, 4)

        await model.findOriginals(in: relocated, operation: .reconnect, originalIDs: [firstVersion.originalID, secondVersion.originalID])
        var latest = try repository.load()
        latest.photos[4].trashedAt = Date()
        latest.photos[5].people = try detections()
        _ = try repository.save(latest)
        await model.reloadLibrary()
        model.scope = "project:\(other.id)"
        model.selection = outsideVersion.id
        let unretried = try repository.load()
        let started = expectation(description: "Retry reached the second original")
        let gate = AsyncStream<Void>.makeStream()
        defer { gate.continuation.finish() }
        model.retryPeopleScan(report) { image in
            if image.width == 128 {
                started.fulfill()
                for await _ in gate.stream {}
            }
            return []
        }
        let cancelled = try XCTUnwrap(model.peopleScan)
        await fulfillment(of: [started], timeout: 5)
        XCTAssertEqual(cancelled.progress.counts, PeopleScanCounts(total: 2, checked: 1))
        cancelled.progress.cancel(cancelled.task)
        _ = await cancelled.task.result
        try await waitForScan(model)
        XCTAssertEqual(model.peopleScanReport?.id, report.id)
        XCTAssertTrue(try repository.load().hasSameCatalogueRevision(as: unretried))

        model.retryPeopleScan(report)
        let retry = try XCTUnwrap(model.peopleScan)
        let result = try await retry.task.value
        try await waitForScan(model)
        XCTAssertEqual(result.changes.map(\.photoID), [firstVersion.id, secondVersion.id])
        XCTAssertTrue(result.skippedVersions.isEmpty)
        XCTAssertFalse(model.canOpenPeopleScanReport)
        XCTAssertNil(model.library.photos.first { $0.id == outsideShared.id }?.people)
        XCTAssertNil(model.library.photos.first { $0.id == outsideVersion.id }?.people)
        XCTAssertEqual(model.history.undo.count, (unretried.history?.undo.count ?? 0) + 1)
        model.undoEdit()
        XCTAssertEqual(try repository.load().photos, unretried.photos)
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

    private func makeImage(_ url: URL, red: CGFloat = 0.7, width: Int = 96) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(red: red, green: 0.3, blue: 0.2, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: 64))
        let image = try XCTUnwrap(ctx.makeImage())
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }
}
