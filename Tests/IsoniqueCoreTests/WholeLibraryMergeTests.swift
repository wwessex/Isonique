import XCTest
@testable import IsoniqueCore

final class WholeLibraryMergeTests: XCTestCase {
    func testReadOnlyPreviewCountsProjectsVersionsAndDistinctOriginals() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let sourceURL = fixture.source.root.appendingPathComponent("catalog.json")
        let destinationURL = fixture.destination.root.appendingPathComponent("catalog.json")
        let sourceBefore = try Data(contentsOf: sourceURL)
        let destinationBefore = try Data(contentsOf: destinationURL)
        // Preflight should neither read originals nor create a missing Originals directory.
        let sourceOriginals = fixture.source.root.appendingPathComponent("Originals")
        try FileManager.default.removeItem(at: sourceOriginals)

        let preview = try fixture.destination.previewLibraryMerge(from: fixture.source.root)

        XCTAssertEqual(preview.projects.map(\.name), ["Shared Project in Source", "Imported Project", "Empty Project", "Unassigned photos"])
        XCTAssertEqual(preview.projects.map(\.isNew), [false, true, true, false])
        XCTAssertEqual(preview.projects.map(\.photosToAdd), [1, 2, 0, 1])
        XCTAssertEqual(preview.projects.map(\.matchingPhotos), [1, 0, 0, 0])
        XCTAssertEqual(preview.photosToAdd, 4)
        XCTAssertEqual(preview.albumsToAdd, 2)
        XCTAssertEqual(preview.originalsToCopy, 2)
        XCTAssertEqual(preview.reusableOriginals, 1)
        XCTAssertEqual(preview.sharedOriginalsInSource, 2)
        XCTAssertEqual(preview.trashedPhotosExcluded, 1)
        XCTAssertTrue(preview.conflicts.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sourceOriginals.path))
        XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        XCTAssertEqual(try Data(contentsOf: destinationURL), destinationBefore)
    }

    func testPreflightReportsIncompatibleFingerprintsAndAlbumTypes() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var source = try fixture.source.load()
        for index in source.photos.indices where source.photos[index].originalID == fixture.sharedPhoto.id {
            source.photos[index].sha256 = "incompatible"
        }
        source.albums[0].rule = SmartAlbumRule()
        source.photos[0].albumIDs.removeAll()
        try fixture.source.save(source)

        let preview = try fixture.destination.previewLibraryMerge(from: fixture.source.root, photoPolicy: .preferIncoming)

        XCTAssertEqual(preview.reusableOriginals, 0)
        XCTAssertEqual(preview.conflicts.count, 2)
        XCTAssertTrue(preview.conflicts.contains { $0.hasPrefix("Album identity —") })
        XCTAssertTrue(preview.conflicts.contains { $0.hasPrefix("Original fingerprint —") })
        XCTAssertTrue(preview.photoDifferences.isEmpty)
        XCTAssertEqual(preview.photosToUpdate, 0)
    }

    func testPreflightRejectsTheCurrentLibraryEvenThroughASymlink() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let alias = fixture.root.appendingPathComponent("Alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.destination.root)
        for source in [fixture.destination.root, alias] {
            XCTAssertThrowsError(try fixture.destination.previewLibraryMerge(from: source)) { error in
                guard case LibraryError.unsafePath = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testMergePreservesMatchingRecordsAndReopensSharedOriginalsAndMemberships() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let destinationBefore = try fixture.destination.load()
        let sourceBefore = try snapshot(fixture.source)
        let referenceHash = try LibraryRepository.digest(fixture.externalOriginal)

        let result = try await fixture.destination.mergeLibrary(from: fixture.source.root, review: {
            XCTAssertEqual($0.photosToAdd, 4)
            XCTAssertTrue($0.conflicts.isEmpty)
            return true
        })

        let (repository, saved) = try LibraryBackup.openVerified(fixture.destination.root)
        let byID = Dictionary(uniqueKeysWithValues: saved.photos.map { ($0.id, $0) })
        let reused = try XCTUnwrap(byID[fixture.reusedVersion.id])
        let added = try XCTUnwrap(byID[fixture.incomingPhoto.id])
        let version = try XCTUnwrap(byID[fixture.incomingVersion.id])
        let unassigned = try XCTUnwrap(byID[fixture.unassigned.id])
        XCTAssertEqual(result.preview.originalsToCopy, 2)
        XCTAssertEqual(saved.projects.map(\.name), ["Shared Project", "Local Project", "Imported Project", "Empty Project"])
        XCTAssertEqual(saved.albums.map(\.name), ["Shared Selects", "Imported Selects", "Imported Flagged"])
        XCTAssertEqual(saved.albums.last?.rule?.projectID, version.projectID)
        XCTAssertEqual(Array(saved.photos.prefix(2)), destinationBefore.photos)
        XCTAssertEqual(reused.filename, fixture.sharedPhoto.filename)
        XCTAssertEqual(reused.originalID, fixture.sharedPhoto.id)
        XCTAssertEqual(version.filename, added.filename)
        XCTAssertEqual(version.originalID, added.id)
        XCTAssertEqual(added.adjustments.exposure, 0.4)
        XCTAssertEqual(added.albumIDs, version.albumIDs)
        XCTAssertEqual(added.albumIDs, [saved.albums[1].id])
        XCTAssertNotEqual(added.projectID, version.projectID)
        XCTAssertEqual(reused.pairID, fixture.pairID)
        XCTAssertEqual(added.pairID, fixture.pairID)
        XCTAssertEqual(saved.stackBrowser?.picks[fixture.stackID], version.id)
        XCTAssertEqual(saved.stackBrowser?.albumPicks[saved.albums[1].id]?[fixture.stackID], added.id)
        XCTAssertEqual(saved.stackBrowser?.collapsed, [fixture.stackID])
        XCTAssertNil(unassigned.projectID)
        XCTAssertNil(unassigned.referencedPath)
        XCTAssertEqual(try LibraryRepository.digest(repository.availableOriginalURL(unassigned)), referenceHash)
        XCTAssertEqual(try LibraryBackup.verify(repository), 4)
        XCTAssertEqual(try snapshot(fixture.source), sourceBefore)
        XCTAssertEqual(try LibraryRepository.digest(fixture.externalOriginal), referenceHash)

        let savedBeforeRetry = try snapshot(repository)
        let retry = try await repository.mergeLibrary(from: fixture.source.root, review: {
            XCTAssertFalse($0.hasAdditions)
            return true
        })
        XCTAssertFalse(retry.preview.hasAdditions)
        XCTAssertEqual(try snapshot(repository), savedBeforeRetry)
    }

    func testOptInReviewsMatchingFieldsAndAppliesOnlyTheChosenPolicy() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var current = try fixture.destination.load()
        var localTrash = fixture.sharedPhoto
        localTrash.id = UUID()
        localTrash.sharedOriginalID = fixture.sharedPhoto.id
        localTrash.trashedAt = Date()
        var incomingTrash = localTrash
        incomingTrash.id = UUID()
        incomingTrash.trashedAt = nil
        current.photos += [localTrash, incomingTrash]
        current.version = 3
        try fixture.destination.save(current)

        var source = try fixture.source.load()
        var edited = try XCTUnwrap(source.photos.first { $0.id == fixture.sharedPhoto.id })
        edited.adjustments.exposure = 0.85
        edited.adjustments.crop = PhotoCrop(x: 0.1, y: 0.1, width: 0.7, height: 0.7)
        edited.rating = 5
        edited.flagged = true
        edited.colorLabel = .blue
        edited.keywords = "delivery, landscape"
        edited.captureDate = "2026:06:11 12:00:00"
        edited.versions = [PhotoVersion(name: "Delivery recipe", adjustments: edited.adjustments)]
        edited.albumIDs = []
        edited.projectID = nil
        edited.stackID = UUID()
        edited.pairID = UUID()
        var activeOnSource = localTrash
        activeOnSource.trashedAt = nil
        activeOnSource.caption = "Keep in destination Trash"
        var trashOnSource = incomingTrash
        trashOnSource.trashedAt = Date()
        trashOnSource.caption = "Keep active in the destination"
        source.photos = [edited, activeOnSource, trashOnSource]
        source.projects = [current.projects[0]]
        source.albums = current.albums
        source.stackBrowser = nil
        try fixture.source.save(source)

        let destinationBefore = try snapshot(fixture.destination)
        let sourceBefore = try snapshot(fixture.source)
        let defaultPreview = try fixture.destination.previewLibraryMerge(from: fixture.source.root)
        XCTAssertEqual(defaultPreview.photoPolicy, .addOnly)
        XCTAssertTrue(defaultPreview.photoDifferences.isEmpty)
        XCTAssertFalse(defaultPreview.hasChanges)

        let fields = ["Exposure", AdjustmentGroup.geometry.rawValue, "Saved recipes", "Rating", "Flag",
                      "Color label", "Caption", "Keywords", "Capture date"]
        let kept = try await fixture.destination.mergeLibrary(from: fixture.source.root, photoPolicy: .preferCurrent, review: {
            XCTAssertEqual($0.photoDifferences.map(\.fields), [fields])
            XCTAssertEqual($0.photoDifferences.first?.projectName, "Shared Project")
            XCTAssertEqual($0.photoDifferences.first?.photoName, "Shared.png")
            XCTAssertEqual($0.photosToUpdate, 0)
            XCTAssertFalse($0.hasChanges)
            return true
        })
        XCTAssertEqual(kept.library.photos, current.photos)
        XCTAssertEqual(try snapshot(fixture.destination), destinationBefore)

        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, photoPolicy: .preferIncoming, review: {
                XCTAssertEqual($0.photoDifferences.map(\.fields), [fields])
                XCTAssertEqual($0.photosToUpdate, 1)
                XCTAssertFalse($0.hasAdditions)
                XCTAssertTrue($0.hasChanges)
                return false
            })
            XCTFail("Expected declined matching-photo updates to cancel")
        } catch is CancellationError {}
        XCTAssertEqual(try snapshot(fixture.destination), destinationBefore)

        let applied = try await fixture.destination.mergeLibrary(from: fixture.source.root, photoPolicy: .preferIncoming, review: { _ in true })
        let (repository, saved) = try LibraryBackup.openVerified(fixture.destination.root)
        var expected = current.photos
        expected[0].adjustments = edited.adjustments
        expected[0].versions = edited.versions
        expected[0].rating = edited.rating
        expected[0].flagged = edited.flagged
        expected[0].colorLabel = edited.colorLabel
        expected[0].caption = edited.caption
        expected[0].keywords = edited.keywords
        expected[0].captureDate = edited.captureDate
        XCTAssertEqual(applied.preview.photosToUpdate, 1)
        XCTAssertEqual(applied.preview.originalsToCopy, 0)
        XCTAssertEqual(saved.photos, expected)
        XCTAssertEqual(try LibraryBackup.verify(repository), 2)
        XCTAssertEqual(try snapshot(repository).originals, destinationBefore.originals)
        XCTAssertEqual(try snapshot(fixture.source), sourceBefore)
    }

    func testMatchingPhotoUpdatesRollBackWithFailedAdditionsAndRequireVerifiedOriginal() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try snapshot(fixture.destination)
        let externalBytes = try Data(contentsOf: fixture.externalOriginal)
        try Data([42]).write(to: fixture.externalOriginal)
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, photoPolicy: .preferIncoming, review: {
                XCTAssertEqual($0.photosToUpdate, 1)
                XCTAssertEqual($0.photosToAdd, 4)
                return true
            })
            XCTFail("Expected corrupt addition to block the entire merge")
        } catch LibraryError.integrity(let name) {
            XCTAssertEqual(name, fixture.unassigned.originalName)
        }
        XCTAssertEqual(try snapshot(fixture.destination), before)
        try externalBytes.write(to: fixture.externalOriginal)

        var incoming = try fixture.source.load()
        incoming.photos = incoming.photos.filter { $0.id == fixture.sharedPhoto.id }
        incoming.stackBrowser = nil
        let current = try fixture.destination.load()
        incoming.projects = [current.projects[0]]
        incoming.albums = current.albums
        try fixture.source.save(incoming)
        let original = try fixture.destination.availableOriginalURL(fixture.sharedPhoto)
        try Data([41]).write(to: original)
        let corrupt = try snapshot(fixture.destination)
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, photoPolicy: .preferIncoming, review: {
                XCTAssertEqual($0.photosToUpdate, 1)
                XCTAssertFalse($0.hasAdditions)
                return true
            })
            XCTFail("Expected edit-only merge to verify its original")
        } catch LibraryError.integrity(let name) {
            XCTAssertEqual(name, fixture.sharedPhoto.originalName)
        }
        XCTAssertEqual(try snapshot(fixture.destination), corrupt)
    }

    func testExplicitTrashIsOptInAndPreservesSharedOriginalsAndPutBack() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let date = Date(timeIntervalSinceReferenceDate: 100)
        var current = try fixture.destination.load()
        current.photos[0].adjustments.exposure = 0.7
        let visibleVersion = try XCTUnwrap(current.createVersion(of: fixture.sharedPhoto.id, from: .current))
        let alreadyTrashed = try XCTUnwrap(current.createVersion(of: fixture.sharedPhoto.id, from: .current))
        current.photos[3].trashedAt = date.addingTimeInterval(-10)
        let stack = UUID()
        current.photos[0].stackID = stack
        current.photos[2].stackID = stack
        current.applyStackPick(StackPickChange(stackID: stack, photoID: fixture.sharedPhoto.id, selectionID: fixture.sharedPhoto.id))
        try fixture.destination.save(current)

        var source = try fixture.source.load()
        var sourceTrash = try XCTUnwrap(source.photos.first { $0.id == fixture.sharedPhoto.id })
        sourceTrash.trashedAt = date
        var earlierTrash = alreadyTrashed
        earlierTrash.trashedAt = date
        let sourceOnlyTrash = try XCTUnwrap(source.photos.first { $0.trashedAt != nil })
        source.photos = [sourceTrash, current.photos[2], earlierTrash, sourceOnlyTrash]
        source.projects = [current.projects[0], try XCTUnwrap(source.projects.first { $0.id == sourceOnlyTrash.projectID })]
        // The project that only contains an excluded Trash record already exists on both sides.
        current.projects.append(source.projects[1])
        source.albums = current.albums
        source.stackBrowser = nil
        try fixture.destination.save(current)
        try fixture.source.save(source)
        let before = try snapshot(fixture.destination)
        let sourceBefore = try snapshot(fixture.source)

        let defaultResult = try await fixture.destination.mergeLibrary(from: fixture.source.root, review: {
            XCTAssertTrue($0.trashMoves.isEmpty)
            XCTAssertEqual($0.trashedPhotosExcluded, 3)
            XCTAssertFalse($0.hasChanges)
            return true
        })
        XCTAssertEqual(defaultResult.library.photos, current.photos)
        XCTAssertEqual(try snapshot(fixture.destination), before)

        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, applyTrash: true, review: {
                XCTAssertEqual($0.trashMoves.map(\.photoID), [fixture.sharedPhoto.id])
                XCTAssertEqual($0.trashMoves.map(\.photoName), ["Shared.png"])
                XCTAssertEqual($0.trashMoves.first?.projectName, "Shared Project")
                XCTAssertEqual($0.trashedPhotosExcluded, 2)
                XCTAssertTrue($0.hasChanges)
                XCTAssertFalse($0.hasAdditions)
                return false
            })
            XCTFail("Expected declined Trash review to cancel")
        } catch is CancellationError {}
        XCTAssertEqual(try snapshot(fixture.destination), before)

        let result = try await fixture.destination.mergeLibrary(from: fixture.source.root, photoPolicy: .preferIncoming,
                                                                 applyTrash: true, review: { _ in true })
        let (repository, saved) = try LibraryBackup.openVerified(fixture.destination.root)
        var expected = current.photos
        expected[0].trashedAt = date
        XCTAssertEqual(result.preview.photosToUpdate, 0)
        XCTAssertEqual(result.preview.originalsToCopy, 0)
        XCTAssertEqual(saved.photos, expected)
        XCTAssertEqual(saved.stackBrowser, current.stackBrowser)
        XCTAssertTrue(saved.activePhotos.contains { $0.id == visibleVersion.id })
        XCTAssertEqual(try snapshot(repository).originals, before.originals)
        XCTAssertEqual(try snapshot(fixture.source), sourceBefore)
        let merged = try snapshot(repository)
        let retry = try await repository.mergeLibrary(from: fixture.source.root, applyTrash: true, review: {
            XCTAssertTrue($0.trashMoves.isEmpty)
            XCTAssertFalse($0.hasChanges)
            return true
        })
        XCTAssertFalse(retry.preview.hasChanges)
        XCTAssertEqual(try snapshot(repository), merged)

        var restored = saved
        XCTAssertEqual(restored.setPhotosTrashed([fixture.sharedPhoto.id], at: nil), [expected[0]])
        try repository.save(restored)
        let (_, reopened) = try LibraryBackup.openVerified(repository.root)
        XCTAssertEqual(reopened.photos, current.photos)
        XCTAssertEqual(try snapshot(repository).originals, before.originals)
    }

    func testTrashIdentityConflictsBlockPublication() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try snapshot(fixture.destination)
        var source = try fixture.source.load()
        let shared = try XCTUnwrap(source.photos.first { $0.id == fixture.sharedPhoto.id })
        for changeOriginalID in [true, false] {
            var trashed = shared
            trashed.trashedAt = Date()
            if changeOriginalID { trashed.sharedOriginalID = UUID() }
            else { trashed.sha256 = String(repeating: "0", count: 64) }
            source.photos = [trashed]
            source.stackBrowser = nil
            try fixture.source.save(source)
            XCTAssertTrue(try fixture.destination.previewLibraryMerge(from: fixture.source.root).conflicts.isEmpty)
            do {
                _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, applyTrash: true, review: {
                    XCTAssertTrue($0.trashMoves.isEmpty)
                    XCTAssertEqual($0.conflicts.count, 1)
                    XCTAssertTrue($0.conflicts[0].hasPrefix("Trash identity — Shared.png"))
                    return true
                })
                XCTFail("Expected mismatched Trash identity to block publication")
            } catch LibraryMergeError.identityConflicts {}
            XCTAssertEqual(try snapshot(fixture.destination), before)
        }
    }

    func testTrashMovesAndAdditionsRollBackTogetherOnSaveFailure() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var source = try fixture.source.load()
        let index = try XCTUnwrap(source.photos.firstIndex { $0.id == fixture.sharedPhoto.id })
        source.photos[index].trashedAt = Date()
        try fixture.source.save(source)
        let before = try snapshot(fixture.destination)
        let sourceBefore = try snapshot(fixture.source)
        let catalogue = fixture.destination.root.appendingPathComponent("catalog.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, applyTrash: true, review: {
                XCTAssertEqual($0.trashMoves.map(\.photoID), [fixture.sharedPhoto.id])
                XCTAssertEqual($0.photosToAdd, 4)
                XCTAssertEqual($0.originalsToCopy, 2)
                return true
            })
            XCTFail("Expected catalogue save failure")
        } catch is CocoaError {}
        XCTAssertEqual(try snapshot(fixture.destination), before)
        XCTAssertEqual(try snapshot(fixture.source), sourceBefore)
    }

    func testDecliningAndCancellingThenFailedSaveLeaveNoAdditions() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try snapshot(fixture.destination)
        let sourceBefore = try snapshot(fixture.source)
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, review: { _ in false }, progress: { _ in
                XCTFail("A declined review should skip staging")
            })
            XCTFail("Expected a declined review to cancel")
        } catch is CancellationError {}
        XCTAssertEqual(try snapshot(fixture.destination), before)

        let job = Task.detached {
            try await fixture.destination.mergeLibrary(from: fixture.source.root, review: { _ in true }, progress: {
                if $0.processed == 1 { withUnsafeCurrentTask { $0?.cancel() } }
            })
        }
        do {
            _ = try await job.value
            XCTFail("Expected cancellation during staging")
        } catch is CancellationError {}
        XCTAssertEqual(try snapshot(fixture.destination), before)

        let catalogue = fixture.destination.root.appendingPathComponent("catalog.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, review: { _ in true })
            XCTFail("Expected catalogue save failure")
        } catch is CocoaError {}
        XCTAssertEqual(try snapshot(fixture.destination), before)
        XCTAssertEqual(try snapshot(fixture.source), sourceBefore)
    }

    func testRechecksCatalogueAndOriginalsAfterReview() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let before = try snapshot(fixture.destination)
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, review: { _ in true }, progress: {
                guard $0.processed == 1 else { return }
                do {
                    var edited = try fixture.source.load()
                    edited.projects[0].name = "Changed during staging"
                    try fixture.source.save(edited)
                } catch { XCTFail("Fixture could not modify the source: \(error)") }
            })
            XCTFail("Expected a source catalogue change to block publication")
        } catch LibraryError.integrity(let message) {
            XCTAssertTrue(message.contains("source catalogue changed"))
        }
        XCTAssertEqual(try snapshot(fixture.destination), before)

        try Data([42]).write(to: fixture.externalOriginal)
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, review: { _ in true })
            XCTFail("Expected an external original fingerprint mismatch")
        } catch LibraryError.integrity(let name) {
            XCTAssertEqual(name, fixture.unassigned.originalName)
        }
        XCTAssertEqual(try snapshot(fixture.destination), before)
    }

    func testCannotApproveStackAndUndoIdentityConflicts() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var library = try fixture.destination.load()
        library.setStackCollapsed(true, stackID: fixture.stackID)
        try fixture.destination.save(library)
        let before = try snapshot(fixture.destination)
        var history = EditHistory()
        history.record(.restoreVersion(fixture.reusedVersion))
        do {
            _ = try await fixture.destination.mergeLibrary(from: fixture.source.root, reserving: history, review: {
                XCTAssertEqual($0.conflicts.count, 2)
                XCTAssertTrue($0.conflicts.contains { $0.hasPrefix("Stack identity —") })
                XCTAssertTrue($0.conflicts.contains { $0.contains("reserved by destination edit history") })
                return true
            })
            XCTFail("Expected identity conflicts to block publication")
        } catch LibraryMergeError.identityConflicts {}
        XCTAssertEqual(try snapshot(fixture.destination), before)
    }

    private struct Snapshot: Equatable {
        let catalogue: Data
        let entries: Set<String>
        let originals: [String: String]
    }

    private func snapshot(_ repository: LibraryRepository) throws -> Snapshot {
        let files = FileManager.default
        let root = repository.root
        let originals = root.appendingPathComponent("Originals")
        let hashes = try files.contentsOfDirectory(atPath: originals.path).map { name in
            (name, try LibraryRepository.digest(originals.appendingPathComponent(name)))
        }
        return Snapshot(catalogue: try Data(contentsOf: root.appendingPathComponent("catalog.json")),
                        entries: Set(try files.contentsOfDirectory(atPath: root.path)),
                        originals: Dictionary(uniqueKeysWithValues: hashes))
    }

    private struct Fixture {
        let root: URL
        let destination: LibraryRepository
        let source: LibraryRepository
        let sharedPhoto: Photo
        let reusedVersion: Photo
        let incomingPhoto: Photo
        let incomingVersion: Photo
        let unassigned: Photo
        let externalOriginal: URL
        let stackID: UUID
        let pairID: UUID
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueWholeMerge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let destination = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Current"))
        let source = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Incoming"))
        let shared = Collection(name: "Shared Project")
        let local = Collection(name: "Local Project")
        let imported = Collection(name: "Imported Project")
        let empty = Collection(name: "Empty Project")
        let sharedAlbum = Collection(name: "Shared Selects")
        let album = Collection(name: "Imported Selects")
        var smartAlbum = Collection(name: "Imported Flagged")
        smartAlbum.rule = SmartAlbumRule(flaggedOnly: true)
        smartAlbum.rule?.projectID = imported.id
        var sharedPhoto = try photo("Shared.png", byte: 1, project: shared.id, in: destination)
        sharedPhoto.caption = "Local caption"
        sharedPhoto.albumIDs = [sharedAlbum.id]
        let localOnly = try photo("Local.png", byte: 2, project: local.id, in: destination)
        var current = Library()
        current.projects = [shared, local]
        current.albums = [sharedAlbum]
        current.photos = [sharedPhoto, localOnly]
        try destination.save(current)

        var renamed = shared
        renamed.name = "Shared Project in Source"
        var sourceShared = sharedPhoto
        sourceShared.caption = "Incoming caption"
        try FileManager.default.copyItem(at: destination.managedOriginalURL(sharedPhoto.filename),
                                         to: source.managedOriginalURL(sharedPhoto.filename))
        var incomingPhoto = try photo("Local.png", byte: 3, project: shared.id, in: source)
        incomingPhoto.albumIDs = [album.id]
        incomingPhoto.adjustments.exposure = 0.4
        var unassigned = try photo("Unassigned.png", byte: 4, project: nil, in: source)
        let externalOriginal = root.appendingPathComponent("Referenced.png")
        try FileManager.default.moveItem(at: source.managedOriginalURL(unassigned.filename), to: externalOriginal)
        unassigned.referencedPath = externalOriginal.path
        var trashed = try photo("Trashed.png", byte: 5, project: imported.id, in: source)
        trashed.trashedAt = Date()
        var incoming = Library()
        incoming.projects = [renamed, imported, empty]
        incoming.albums = [sharedAlbum, album, smartAlbum]
        incoming.photos = [sourceShared, incomingPhoto, unassigned, trashed]
        let reused = try XCTUnwrap(incoming.createVersion(of: sourceShared.id, from: .current))
        let version = try XCTUnwrap(incoming.createVersion(of: incomingPhoto.id, from: .current))
        incoming.photos[4].projectID = imported.id
        incoming.photos[4].albumIDs = []
        incoming.photos[5].projectID = imported.id
        let stackID = UUID()
        let pairID = UUID()
        incoming.photos[1].stackID = stackID
        incoming.photos[5].stackID = stackID
        incoming.photos[1].pairID = pairID
        incoming.photos[4].pairID = pairID
        incoming.setStackCollapsed(true, stackID: stackID)
        incoming.applyStackPick(StackPickChange(stackID: stackID, photoID: version.id, selectionID: version.id))
        incoming.applyStackPick(StackPickChange(stackID: stackID, albumID: album.id, photoID: incomingPhoto.id,
                                               selectionID: incomingPhoto.id))
        try source.save(incoming)
        return Fixture(root: root, destination: destination, source: source, sharedPhoto: sharedPhoto,
                       reusedVersion: reused, incomingPhoto: incomingPhoto, incomingVersion: version, unassigned: unassigned,
                       externalOriginal: externalOriginal, stackID: stackID, pairID: pairID)
    }

    private func photo(_ name: String, byte: UInt8, project: UUID?, in repository: LibraryRepository) throws -> Photo {
        let url = try repository.managedOriginalURL(name)
        try Data([byte]).write(to: url)
        return Photo(filename: name, originalName: name, projectID: project, width: 8, height: 6,
                     camera: "", captureDate: "", sha256: try LibraryRepository.digest(url))
    }
}
