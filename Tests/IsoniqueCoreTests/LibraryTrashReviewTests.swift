import XCTest
@testable import IsoniqueCore

final class LibraryTrashReviewTests: XCTestCase {
    func testReviewProtectsSharedAndReferencedOriginalsAndDoesNotWrite() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = Collection(name: "Portraits")
        var library = Library()
        library.projects = [project]
        let shared = try managed("Shared.png", byte: 1, project: project.id, in: repository)
        let allTrashed = try managed("All trashed.png", byte: 2, project: project.id, in: repository)
        let missing = try managed("Missing.png", byte: 3, project: project.id, in: repository)
        let external = folder.appendingPathComponent("External.png")
        try Data([4]).write(to: external)
        var referenced = Photo(filename: "Referenced.png", originalName: "Referenced.png", projectID: nil,
                               width: 8, height: 6, camera: "", captureDate: "", sha256: try LibraryRepository.digest(external))
        referenced.referencedPath = external.path
        library.photos = [shared, allTrashed, missing, referenced]
        let activeVersion = try XCTUnwrap(library.createVersion(of: shared.id, from: .current))
        let trashedVersion = try XCTUnwrap(library.createVersion(of: allTrashed.id, from: .current))
        let trashedIDs = Set([shared.id, allTrashed.id, missing.id, referenced.id, trashedVersion.id])
        _ = library.setPhotosTrashed(trashedIDs, at: Date())
        try repository.save(library)
        try FileManager.default.removeItem(at: repository.managedOriginalURL(missing.filename))
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        let filesBefore = try managedHashes(repository)
        let externalBefore = try Data(contentsOf: external)

        let review = try repository.reviewEmptyLibraryTrash()

        XCTAssertEqual(Set(review.photos.map(\.id)), trashedIDs)
        XCTAssertFalse(review.photos.contains { $0.id == activeVersion.id })
        XCTAssertEqual(review.photos.first { $0.id == shared.id }?.projectName, project.name)
        XCTAssertNil(review.photos.first { $0.id == referenced.id }?.projectName)
        let dispositions = Dictionary(uniqueKeysWithValues: review.originals.map { ($0.id, $0.disposition) })
        XCTAssertEqual(dispositions, [
            shared.id: .retainedByActiveVersion,
            allTrashed.id: .finderTrashCandidate,
            missing.id: .unavailable,
            referenced.id: .referenced
        ])
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertEqual(try managedHashes(repository), filesBefore)
        XCTAssertEqual(try Data(contentsOf: external), externalBefore)
    }

    func testReviewExcludesSymlinksAndAmbiguousManagedNames() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let active = try managed("Active.png", byte: 1, project: nil, in: repository)
        let ambiguous = try managed("Ambiguous.png", byte: 2, project: nil, in: repository)
        var activeAlias = active
        activeAlias.id = UUID()
        activeAlias.filename = "ACTIVE.png"
        var otherAlias = ambiguous
        otherAlias.id = UUID()
        otherAlias.filename = "AMBIGUOUS.png"
        var link = active
        link.id = UUID()
        link.filename = "Link.png"
        let linkURL = try repository.managedOriginalURL(link.filename)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: repository.managedOriginalURL(active.filename))
        var library = Library()
        library.photos = [active, activeAlias, ambiguous, otherAlias, link]
        _ = library.setPhotosTrashed([activeAlias.id, ambiguous.id, otherAlias.id, link.id], at: Date())
        try repository.save(library)

        let review = try repository.reviewEmptyLibraryTrash()

        XCTAssertEqual(Dictionary(uniqueKeysWithValues: review.originals.map { ($0.id, $0.disposition) }), [
            activeAlias.id: .retainedByActiveVersion,
            ambiguous.id: .unavailable,
            otherAlias.id: .unavailable,
            link.id: .unavailable
        ])
        XCTAssertTrue(try XCTUnwrap(linkURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink))
    }

    func testEmptyLibraryTrashReturnsAnEmptyReview() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let review = try repository.reviewEmptyLibraryTrash()
        XCTAssertTrue(review.photos.isEmpty)
        XCTAssertTrue(review.originals.isEmpty)
    }

    func testPartialHandoffPersistsRetryAndProtectsSharedAndReferencedOriginals() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = FileManager.default
        let handedOff = folder.appendingPathComponent("Finder fixture")
        try files.createDirectory(at: handedOff, withIntermediateDirectories: false)
        let shared = try managed("Shared.png", byte: 1, project: nil, in: repository)
        let first = try managed("First.png", byte: 2, project: nil, in: repository)
        let second = try managed("Second.png", byte: 3, project: nil, in: repository)
        let missing = try managed("Missing.png", byte: 4, project: nil, in: repository)
        let external = folder.appendingPathComponent("External.png")
        try Data([5]).write(to: external)
        var referenced = Photo(filename: "Referenced.png", originalName: "Referenced.png", projectID: nil,
                               width: 8, height: 6, camera: "", captureDate: "", sha256: try LibraryRepository.digest(external))
        referenced.referencedPath = external.path
        var library = Library()
        library.photos = [shared, first, second, missing, referenced]
        let active = try XCTUnwrap(library.createVersion(of: shared.id, from: .current))
        let versionOfFirst = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        let trashed = Set([shared.id, first.id, second.id, missing.id, referenced.id, versionOfFirst.id])
        let stack = UUID()
        library.photos[0].stackID = stack
        library.photos[5].stackID = stack
        library.applyStackPick(StackPickChange(stackID: stack, photoID: shared.id, selectionID: shared.id))
        library.history = EditHistory()
        library.history?.record(active)
        library.history?.record(shared)
        _ = library.setPhotosTrashed(trashed, at: Date())
        try repository.save(library)
        try files.removeItem(at: repository.managedOriginalURL(missing.filename))
        let review = try repository.reviewEmptyLibraryTrash()
        var calls: [String] = []
        let result = try repository.emptyLibraryTrash(after: review) { original in
            calls.append(original.lastPathComponent)
            XCTAssertThrowsError(try repository.save(library), "Catalogue writes must share the handoff lock")
            if original.lastPathComponent == second.filename { throw CocoaError(.fileWriteNoPermission) }
            try files.moveItem(at: original, to: handedOff.appendingPathComponent(original.lastPathComponent))
        }
        XCTAssertEqual(calls, [first.filename, second.filename])
        XCTAssertEqual(result.removedPhotoIDs, trashed.subtracting([missing.id]))
        XCTAssertEqual(result.movedToFinderTrash, 1)
        XCTAssertEqual(result.keptInLibrary, 1)
        XCTAssertEqual(result.keptOriginals, [missing.filename])
        XCTAssertEqual(result.pendingFilenames, [second.filename])
        XCTAssertEqual(result.handoffErrors.count, 1)
        XCTAssertEqual(try LibraryRepository.digest(repository.managedOriginalURL(shared.filename)), shared.sha256)
        XCTAssertEqual(try LibraryRepository.digest(external), referenced.sha256)
        XCTAssertEqual(try LibraryRepository.digest(handedOff.appendingPathComponent(first.filename)), first.sha256)
        XCTAssertEqual(try LibraryRepository.digest(repository.managedOriginalURL(second.filename)), second.sha256)

        let reopened = try LibraryRepository(root: repository.root)
        let saved = try reopened.load()
        XCTAssertEqual(saved.photos.map(\.id), [missing.id, active.id])
        XCTAssertEqual(saved.history?.undo.compactMap(\.selectionID), [active.id])
        XCTAssertTrue(saved.stackBrowser?.picks.isEmpty == true)
        let retry = try reopened.reviewEmptyLibraryTrash()
        XCTAssertTrue(retry.canEmpty)
        XCTAssertEqual(retry.pendingFilenames, [second.filename])
        calls = []
        let recovered = try reopened.emptyLibraryTrash(after: retry) { original in
            calls.append(original.lastPathComponent)
            try files.moveItem(at: original, to: handedOff.appendingPathComponent(original.lastPathComponent))
        }
        XCTAssertEqual(calls, [second.filename])
        XCTAssertTrue(recovered.removedPhotoIDs.isEmpty)
        XCTAssertTrue(recovered.pendingFilenames.isEmpty)
        XCTAssertTrue(try reopened.reviewEmptyLibraryTrash().pendingFilenames.isEmpty)
        XCTAssertEqual(try LibraryRepository.digest(handedOff.appendingPathComponent(second.filename)), second.sha256)
    }

    func testChangedCatalogueOrFingerprintCannotUseAnOldReview() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        var photo = try managed("Candidate.png", byte: 1, project: nil, in: repository)
        photo.trashedAt = Date()
        var library = Library()
        library.photos = [photo]
        try repository.save(library)
        let stale = try repository.reviewEmptyLibraryTrash()
        library.photos[0].caption = "Changed since review"
        try repository.save(library)
        XCTAssertThrowsError(try repository.emptyLibraryTrash(after: stale) { _ in XCTFail("Stale review reached Finder") })

        let review = try repository.reviewEmptyLibraryTrash()
        try Data([2]).write(to: repository.managedOriginalURL(photo.filename))
        let result = try repository.emptyLibraryTrash(after: review) { _ in XCTFail("Changed original reached Finder") }
        XCTAssertEqual(result.keptOriginals, [photo.filename])
        XCTAssertTrue(result.removedPhotoIDs.isEmpty)
        XCTAssertTrue(result.pendingFilenames.isEmpty)
        XCTAssertEqual(try repository.load().photos, library.photos)

        try Data([1]).write(to: repository.managedOriginalURL(photo.filename))
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        XCTAssertThrowsError(try repository.emptyLibraryTrash(after: review) { _ in XCTFail("Finder called before publication") })
        XCTAssertEqual(try repository.load().photos, library.photos)
        XCTAssertEqual(try LibraryRepository.digest(repository.managedOriginalURL(photo.filename)), photo.sha256)
    }

    func testRetryReconcilesAMoveWhoseProgressCouldNotBeSaved() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = FileManager.default
        var photo = try managed("Candidate.png", byte: 1, project: nil, in: repository)
        photo.trashedAt = Date()
        var library = Library()
        library.photos = [photo]
        try repository.save(library)
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        defer { try? files.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }

        let review = try repository.reviewEmptyLibraryTrash()
        let partial = try repository.emptyLibraryTrash(after: review) { source in
            try files.moveItem(at: source, to: folder.appendingPathComponent("Moved.png"))
            try files.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        }
        XCTAssertEqual(partial.movedToFinderTrash, 1)
        XCTAssertEqual(partial.pendingFilenames, [photo.filename])
        XCTAssertEqual(partial.handoffErrors.count, 1)
        try files.setAttributes([.immutable: false], ofItemAtPath: catalogue.path)
        let reopened = try LibraryRepository(root: repository.root)
        let retry = try reopened.reviewEmptyLibraryTrash()
        XCTAssertTrue(retry.photos.isEmpty)
        let result = try reopened.emptyLibraryTrash(after: retry) { _ in XCTFail("An absent original must not be moved again") }
        XCTAssertEqual(result.alreadyAbsent, 1)
        XCTAssertTrue(result.pendingFilenames.isEmpty)
        XCTAssertTrue(try reopened.reviewEmptyLibraryTrash().pendingFilenames.isEmpty)
    }

    func testFinderTrashHandoffWithDisposableFile() throws {
        guard ProcessInfo.processInfo.environment["ISONIQUE_TEST_FINDER_TRASH"] == "1" else {
            throw XCTSkip("Set ISONIQUE_TEST_FINDER_TRASH=1 for the native Finder test")
        }
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        var photo = try managed("Isonique-Finder-Test-\(UUID().uuidString).png", byte: 7, project: nil, in: repository)
        photo.trashedAt = Date()
        var library = Library()
        library.photos = [photo]
        try repository.save(library)
        var finderURL: NSURL?
        defer {
            if let finderURL { try? FileManager.default.moveItem(at: finderURL as URL, to: folder.appendingPathComponent("Restored.png")) }
        }
        let result = try repository.emptyLibraryTrash(after: repository.reviewEmptyLibraryTrash()) {
            try FileManager.default.trashItem(at: $0, resultingItemURL: &finderURL)
        }
        XCTAssertEqual(result.removedPhotoIDs, [photo.id])
        XCTAssertEqual(result.movedToFinderTrash, 1, result.handoffErrors.joined(separator: "\n"))
        XCTAssertTrue(result.pendingFilenames.isEmpty)
        let destination = try XCTUnwrap(finderURL) as URL
        XCTAssertEqual(try LibraryRepository.digest(destination), photo.sha256)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try repository.managedOriginalURL(photo.filename).path))
        XCTAssertTrue(try repository.load().photos.isEmpty)
    }

    func testRetryKeepsReplacementBytesAndRetiresAClaimedPath() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        var photo = try managed("Reused.png", byte: 1, project: nil, in: repository)
        photo.trashedAt = Date()
        var library = Library()
        library.photos = [photo]
        try repository.save(library)
        let pending = try repository.emptyLibraryTrash(after: repository.reviewEmptyLibraryTrash()) { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(pending.pendingFilenames, [photo.filename])

        let url = try repository.managedOriginalURL(photo.filename)
        try Data([2]).write(to: url)
        let replaced = try repository.emptyLibraryTrash(after: repository.reviewEmptyLibraryTrash()) { _ in
            XCTFail("Finder was given a replacement file")
        }
        XCTAssertEqual(replaced.pendingFilenames, [photo.filename])
        XCTAssertEqual(replaced.handoffErrors.count, 1)
        XCTAssertEqual(try Data(contentsOf: url), Data([2]))

        // Even the original bytes must stay when a new catalogue record claims the path.
        try Data([1]).write(to: url)
        photo.id = UUID()
        photo.trashedAt = nil
        library = try repository.load()
        library.photos = [photo]
        try repository.save(library)
        let claimed = try repository.emptyLibraryTrash(after: repository.reviewEmptyLibraryTrash()) { _ in
            XCTFail("Finder was given a newly claimed original")
        }
        XCTAssertTrue(claimed.pendingFilenames.isEmpty)
        XCTAssertEqual(try repository.load().photos, [photo])
        XCTAssertEqual(try LibraryRepository.digest(url), photo.sha256)
    }

    private func fixture() throws -> (URL, LibraryRepository) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueTrashReview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return (folder, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library")))
    }

    private func managed(_ name: String, byte: UInt8, project: UUID?, in repository: LibraryRepository) throws -> Photo {
        let url = try repository.managedOriginalURL(name)
        try Data([byte]).write(to: url)
        return Photo(filename: name, originalName: name, projectID: project, width: 8, height: 6,
                     camera: "", captureDate: "", sha256: try LibraryRepository.digest(url))
    }

    private func managedHashes(_ repository: LibraryRepository) throws -> [String: String] {
        let folder = repository.root.appendingPathComponent("Originals")
        return try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: folder.path).map {
            ($0, try LibraryRepository.digest(folder.appendingPathComponent($0)))
        })
    }
}
