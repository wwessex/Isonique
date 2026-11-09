import XCTest
@testable import IsoniqueCore

final class ProjectLibraryMergeTests: XCTestCase {
    func testIncomingValuesAndExplicitTrashMergeWithoutTouchingOtherProjects() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .incoming, applyTrash: true)
        let (reopened, library) = try LibraryBackup.openVerified(fixture.destination.root)
        let photos = Dictionary(uniqueKeysWithValues: library.photos.map { ($0.id, $0) })
        let edited = try XCTUnwrap(photos[fixture.edited.id])
        let addedVersion = try XCTUnwrap(photos[fixture.version.id])
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.trashed, 1)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertEqual(library.projects.count, 2)
        XCTAssertEqual(edited.adjustments.exposure, 0.8)
        XCTAssertEqual(edited.caption, "Incoming caption")
        XCTAssertEqual(edited.versions?.first?.name, "Incoming recipe")
        XCTAssertEqual(edited.albumIDs, [fixture.localAlbum.id, fixture.newAlbum.id])
        XCTAssertEqual(addedVersion.originalID, edited.id)
        XCTAssertEqual(addedVersion.filename, edited.filename)
        XCTAssertEqual(addedVersion.albumIDs, [fixture.newAlbum.id])
        XCTAssertEqual(addedVersion.stackID, edited.stackID)
        XCTAssertEqual(library.stackBrowser?.picks[try XCTUnwrap(edited.stackID)], addedVersion.id)
        XCTAssertEqual(library.stackBrowser?.albumPicks[fixture.newAlbum.id]?[try XCTUnwrap(edited.stackID)], addedVersion.id)
        XCTAssertEqual(library.albums.first(where: { $0.id == fixture.newSmart.id })?.rule?.projectID, fixture.project.id)
        XCTAssertNotNil(photos[fixture.deleted.id]?.trashedAt)
        XCTAssertNil(photos[fixture.absent.id]?.trashedAt)
        XCTAssertEqual(photos[fixture.moved.id], fixture.moved)
        XCTAssertEqual(try LibraryBackup.verify(reopened), 5)
        XCTAssertEqual(try Data(contentsOf: fixture.source.root.appendingPathComponent("catalog.json")), fixture.sourceCatalogue)
    }

    func testCurrentPolicyKeepsEditsAndDoesNotApplyTrash() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .current)
        let saved = try fixture.destination.load()
        let edited = try XCTUnwrap(saved.photos.first { $0.id == fixture.edited.id })
        XCTAssertEqual(result.added, 2)
        XCTAssertEqual(result.trashed, 0)
        XCTAssertEqual(edited.adjustments.exposure, 0.4)
        XCTAssertEqual(edited.caption, "Current caption")
        XCTAssertEqual(edited.albumIDs, [fixture.sharedAlbum.id, fixture.localAlbum.id, fixture.newAlbum.id])
        XCTAssertNil(saved.photos.first { $0.id == fixture.deleted.id }?.trashedAt)
        XCTAssertNil(saved.photos.first { $0.id == fixture.version.id }?.stackID)
        XCTAssertEqual(try LibraryBackup.verify(fixture.destination), 5)
    }

    func testCancellationAndFailedSaveRollBackNewOriginals() async throws {
        let fixture = try fixture(keepsExportMembership: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let root = fixture.destination.root
        let catalogue = root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let files = FileManager.default
        let originals = root.appendingPathComponent("Originals")
        let filenames = Set(try files.contentsOfDirectory(atPath: originals.path))
        let destination = fixture.destination
        let sourceRoot = fixture.source.root
        let job = Task.detached {
            try await destination.mergeProjectLibrary(from: sourceRoot, prefer: .incoming) { progress in
                if progress.processed == progress.total { withUnsafeCurrentTask { $0?.cancel() } }
            }
        }
        do {
            _ = try await job.value
            XCTFail("Expected cancellation before publication")
        } catch is CancellationError {}
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: originals.path)), filenames)

        try files.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? files.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        do {
            _ = try await destination.mergeProjectLibrary(from: sourceRoot, prefer: .incoming)
            XCTFail("Expected the catalogue write to fail")
        } catch {
            XCTAssertTrue(error is CocoaError)
        }
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: originals.path)), filenames)
        XCTAssertFalse(try files.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".isonique-project-import-") })
    }

    func testRejectsWrongProjectAndConflictingOriginalIdentity() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var imported = try fixture.source.load()
        let project = Collection(name: fixture.project.name)
        imported.projects = [project]
        for index in imported.photos.indices { imported.photos[index].projectID = project.id }
        for index in imported.albums.indices where imported.albums[index].rule?.projectID != nil {
            imported.albums[index].rule?.projectID = project.id
        }
        try fixture.source.save(imported)
        do {
            _ = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .incoming)
            XCTFail("Expected stable project ID matching")
        } catch {}

        try fixture.sourceCatalogue.write(to: fixture.source.root.appendingPathComponent("catalog.json"))
        imported = try fixture.source.load()
        for index in imported.photos.indices where imported.photos[index].originalID == fixture.edited.id {
            imported.photos[index].sha256 = "other original"
        }
        try fixture.source.save(imported)
        do {
            _ = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .incoming)
            XCTFail("Expected the original fingerprint conflict to abort")
        } catch {}
        XCTAssertEqual(try LibraryBackup.verify(fixture.destination), 4)
    }

    func testExportMembershipTrashesOnlyPreviouslyExportedMatchingPhotos() async throws {
        let fixture = try fixture(keepsExportMembership: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var incoming = try fixture.source.load()
        let provenance = try XCTUnwrap(incoming.projectExportMembership)
        XCTAssertEqual(provenance.projectID, fixture.project.id)
        XCTAssertNotNil(provenance.originalsByPhoto[fixture.absent.id])
        incoming.photos.removeAll { $0.id == fixture.moved.id }
        try fixture.source.save(incoming)
        var destination = try fixture.destination.load()
        let later = try photo("later.png", byte: 8, project: fixture.project.id, in: fixture.destination)
        destination.photos.append(later)
        try fixture.destination.save(destination)

        let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .incoming, applyTrash: true,
                                                                         review: { preview in
            XCTAssertEqual(preview.projectName, fixture.project.name)
            XCTAssertEqual(preview.trashed, 2)
            XCTAssertEqual(Set(preview.trashNames), [fixture.deleted.displayName, fixture.absent.displayName])
            XCTAssertEqual(preview.skipped, 1)
            XCTAssertEqual(preview.copiedOriginals, 1)
            return true
        })

        let saved = try fixture.destination.load()
        XCTAssertEqual(result.trashed, 2)
        XCTAssertEqual(result.skipped, 1)
        XCTAssertNotNil(saved.photos.first { $0.id == fixture.absent.id }?.trashedAt)
        XCTAssertEqual(saved.photos.first { $0.id == later.id }, later)
        XCTAssertEqual(saved.photos.first { $0.id == fixture.moved.id }, fixture.moved)
    }

    func testRejectingReviewDoesNotStageOrPublishAnyChanges() async throws {
        let fixture = try fixture(keepsExportMembership: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let root = fixture.destination.root
        let catalogue = root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let originals = root.appendingPathComponent("Originals")
        let files = FileManager.default
        let names = Set(try files.contentsOfDirectory(atPath: originals.path))
        var reviewed = false
        do {
            _ = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .incoming, applyTrash: true,
                                                                   review: { preview in
                reviewed = true
                XCTAssertEqual(preview.added, 2)
                XCTAssertEqual(preview.updated, 1)
                XCTAssertEqual(preview.trashed, 2)
                XCTAssertEqual(preview.addedAlbums, 2)
                XCTAssertEqual(preview.copiedOriginals, 1)
                return false
            }, progress: { _ in
                XCTFail("Declining a preview should skip staging")
            })
            XCTFail("Expected declined review to cancel the merge")
        } catch is CancellationError {}
        XCTAssertTrue(reviewed)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: originals.path)), names)
        XCTAssertFalse(try files.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".isonique-project-import-") })
    }

    func testThreeWayMergeKeepsIndependentChangesWithEitherConflictPreference() async throws {
        for preference in [ProjectMergePreference.current, .incoming] {
            let fixture = try fixture(keepsExportMembership: true)
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            var current = try fixture.destination.load()
            current.photos[0].keywords = "Local keywords"
            current.photos[0].rating = 4
            try fixture.destination.save(current)
            var incoming = try fixture.source.load()
            incoming.photos[0].flagged = true
            incoming.photos[0].colorLabel = .blue
            incoming.photos[0].rating = 4
            try fixture.source.save(incoming)

            let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: preference,
                                                                             review: { preview in
                XCTAssertEqual(preview.legacyMatches, 0)
                XCTAssertEqual(preview.conflicts.count, 1)
                XCTAssertEqual(preview.conflicts.first?.photoName, fixture.edited.displayName)
                XCTAssertEqual(preview.conflicts.first?.fields, ["Adjustments", "Caption"])
                return true
            })

            let saved = try fixture.destination.load()
            let edited = try XCTUnwrap(saved.photos.first { $0.id == fixture.edited.id })
            XCTAssertEqual(result.conflicts, 1)
            XCTAssertEqual(edited.adjustments.exposure, preference == .current ? 0.4 : 0.8)
            XCTAssertEqual(edited.caption, preference == .current ? "Current caption" : "Incoming caption")
            XCTAssertEqual(edited.keywords, "Local keywords")
            XCTAssertEqual(edited.rating, 4)
            XCTAssertEqual(edited.colorLabel, .blue)
            XCTAssertTrue(edited.flagged)
            XCTAssertEqual(edited.versions?.first?.name, "Incoming recipe")
            XCTAssertEqual(edited.albumIDs, [fixture.localAlbum.id, fixture.newAlbum.id])
            let version = try XCTUnwrap(saved.photos.first { $0.id == fixture.version.id })
            XCTAssertEqual(version.filename, edited.filename)
            XCTAssertEqual(version.stackID, edited.stackID)
        }
    }

    func testMembershipOnlyExportUsesFallbackAndKeepsItsDeletionEvidence() async throws {
        let fixture = try fixture(keepsExportMembership: true)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let url = fixture.source.root.appendingPathComponent("catalog.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var membership = try XCTUnwrap(object["projectExportMembership"] as? [String: Any])
        let records = try XCTUnwrap(membership["originalsByPhoto"] as? [Any])
        membership["originalsByPhoto"] = records.map { record -> Any in
            guard var record = record as? [String: Any] else { return record }
            record.removeValue(forKey: "values")
            return record
        }
        object["projectExportMembership"] = membership
        try JSONSerialization.data(withJSONObject: object).write(to: url)

        let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .current,
                                                                         applyTrash: true, review: { preview in
            XCTAssertEqual(preview.legacyMatches, 1)
            XCTAssertTrue(preview.conflicts.isEmpty)
            XCTAssertEqual(preview.trashed, 2)
            return true
        })

        XCTAssertEqual(result.conflicts, 0)
        let saved = try fixture.destination.load()
        XCTAssertEqual(saved.photos.first { $0.id == fixture.edited.id }?.adjustments.exposure, 0.4)
        XCTAssertNotNil(saved.photos.first { $0.id == fixture.absent.id }?.trashedAt)
    }

    private struct Fixture {
        let root: URL
        let source: LibraryRepository
        let destination: LibraryRepository
        let project: Collection
        let edited: Photo
        let moved: Photo
        let deleted: Photo
        let absent: Photo
        let version: Photo
        let sharedAlbum: Collection
        let localAlbum: Collection
        let newAlbum: Collection
        let newSmart: Collection
        let sourceCatalogue: Data
    }

    private func fixture(keepsExportMembership: Bool = false) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueProjectMerge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let destination = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Destination"))
        let project = Collection(name: "Shoot")
        let other = Collection(name: "Other project")
        let sharedAlbum = Collection(name: "Shared album")
        let localAlbum = Collection(name: "Local album")
        var edited = try photo("edited.png", byte: 1, project: project.id, in: destination)
        edited.albumIDs = [sharedAlbum.id]
        let deleted = try photo("deleted.png", byte: 2, project: project.id, in: destination)
        let absent = try photo("absent.png", byte: 3, project: project.id, in: destination)
        var moved = try photo("moved.png", byte: 4, project: project.id, in: destination)
        var current = Library()
        current.projects = [project, other]
        current.albums = [sharedAlbum]
        current.photos = [edited, deleted, absent, moved]
        try destination.save(current)
        let exported = root.appendingPathComponent("Exported")
        try LibraryBackup.exportProject(project.id, from: destination, to: exported)
        let (source, opened) = try LibraryBackup.openVerified(exported)

        current.photos[0].adjustments.exposure = 0.4
        current.photos[0].caption = "Current caption"
        current.photos[0].albumIDs.insert(localAlbum.id)
        current.albums.append(localAlbum)
        moved.projectID = other.id
        current.photos[3] = moved
        try destination.save(current)

        var incoming = opened
        if !keepsExportMembership { incoming.projectExportMembership = nil }
        let newAlbum = Collection(name: "Imported album")
        var newSmart = Collection(name: "Imported Smart Album")
        newSmart.rule = SmartAlbumRule()
        incoming.albums += [newAlbum, newSmart]
        incoming.photos[0].adjustments.exposure = 0.8
        incoming.photos[0].caption = "Incoming caption"
        incoming.photos[0].versions = [PhotoVersion(name: "Incoming recipe", adjustments: incoming.photos[0].adjustments)]
        incoming.photos[0].albumIDs = [newAlbum.id]
        let stack = UUID()
        incoming.photos[0].stackID = stack
        incoming.photos[1].trashedAt = Date()
        incoming.photos.removeAll { $0.id == absent.id }
        if let index = incoming.photos.firstIndex(where: { $0.id == moved.id }) {
            incoming.photos[index].caption = "Outside change"
        }
        let version = try XCTUnwrap(incoming.createVersion(of: edited.id, from: .current))
        incoming.applyStackPick(StackPickChange(stackID: stack, photoID: version.id, selectionID: version.id))
        incoming.applyStackPick(StackPickChange(stackID: stack, albumID: newAlbum.id, photoID: version.id, selectionID: version.id))
        incoming.photos.append(try photo("new.png", byte: 5, project: project.id, in: source))
        try source.save(incoming)
        let bytes = try Data(contentsOf: source.root.appendingPathComponent("catalog.json"))
        return Fixture(root: root, source: source, destination: destination, project: project, edited: edited,
                       moved: moved, deleted: deleted, absent: absent, version: version, sharedAlbum: sharedAlbum,
                       localAlbum: localAlbum, newAlbum: newAlbum, newSmart: newSmart, sourceCatalogue: bytes)
    }

    private func photo(_ name: String, byte: UInt8, project: UUID, in repository: LibraryRepository) throws -> Photo {
        let url = try repository.managedOriginalURL(name)
        try Data([byte]).write(to: url)
        return Photo(filename: name, originalName: name, projectID: project,
                     width: 8, height: 6, camera: "", captureDate: "", sha256: try LibraryRepository.digest(url))
    }
}
