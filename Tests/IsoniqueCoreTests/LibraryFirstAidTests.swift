import XCTest
@testable import IsoniqueCore

final class LibraryFirstAidTests: XCTestCase {
    func testSeparatesMissingOfflineAndUntrackedWithoutChangingFiles() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = FileManager.default
        let originals = repository.root.appendingPathComponent("Originals")
        let missing = photo("Missing.png")
        var offline = photo("Reference record.png")
        offline.referencedPath = folder.appendingPathComponent("Disconnected/Offline.png").path
        var availableReference = photo("Available reference.png")
        let external = folder.appendingPathComponent("External.png")
        availableReference.referencedPath = external.path
        try Data([1]).write(to: external)
        var inTrash = photo("In Library Trash.png")
        inTrash.trashedAt = Date()

        var library = Library()
        library.photos = [missing, offline, availableReference, inTrash]
        XCTAssertNotNil(library.createVersion(of: missing.id, from: .current))
        library.pendingFinderTrash = [PendingFinderTrash(filename: "Pending.png", sha256: "fixture")]
        try repository.save(library)
        let managedNames = [inTrash.filename, "Pending.png", "Untracked.png", offline.filename]
        for (index, name) in managedNames.enumerated() {
            try Data([UInt8(index)]).write(to: originals.appendingPathComponent(name))
        }
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let catalogueBefore = try Data(contentsOf: catalogue)
        let filesBefore = try managedNames.map { try Data(contentsOf: originals.appendingPathComponent($0)) }
        let externalBefore = try Data(contentsOf: external)

        let report = try repository.libraryFirstAidReport()

        XCTAssertEqual(report.missingManagedOriginals.map(\.id), [missing.id])
        XCTAssertEqual(report.missingManagedOriginals.first?.location, originals.appendingPathComponent(missing.filename).path)
        XCTAssertEqual(report.offlineReferences.map(\.id), [offline.id])
        XCTAssertEqual(report.offlineReferences.first?.location, offline.referencedPath)
        XCTAssertEqual(report.untrackedManagedFiles, [offline.filename, "Untracked.png"])
        XCTAssertEqual(report.pendingFinderTrash, ["Pending.png"])
        XCTAssertTrue(report.originalsRequiringInspection.isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogue), catalogueBefore)
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: originals.path)), Set(managedNames))
        XCTAssertEqual(try managedNames.map { try Data(contentsOf: originals.appendingPathComponent($0)) }, filesBefore)
        XCTAssertEqual(try Data(contentsOf: external), externalBefore)
    }

    func testUnsafeOriginalPathsAreSeparatedFromMissingFiles() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let originals = repository.root.appendingPathComponent("Originals")
        let target = folder.appendingPathComponent("Outside.png")
        try Data([1]).write(to: target)
        let managedLink = photo("Managed link.png")
        try FileManager.default.createSymbolicLink(at: originals.appendingPathComponent(managedLink.filename),
                                                   withDestinationURL: target)
        var invalidReference = photo("Invalid reference.png")
        invalidReference.referencedPath = originals.appendingPathComponent("Invalid.png").path
        var library = Library()
        library.version = 2
        library.photos = [managedLink, invalidReference]
        try repository.save(library)

        let report = try repository.libraryFirstAidReport()
        XCTAssertEqual(report.originalsRequiringInspection.map(\.id), [managedLink.id, invalidReference.id])
        XCTAssertTrue(report.missingManagedOriginals.isEmpty)
        XCTAssertTrue(report.offlineReferences.isEmpty)
        XCTAssertTrue(report.untrackedManagedFiles.isEmpty)
        XCTAssertEqual(try Data(contentsOf: target), Data([1]))
    }

    func testMissingOriginalsDirectoryStaysAbsentAndSymlinkCannotRedirectScan() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let files = FileManager.default
        let originals = repository.root.appendingPathComponent("Originals")
        let missing = photo("Missing.png")
        var library = Library()
        library.photos = [missing]
        try repository.save(library)
        try files.removeItem(at: originals)

        let report = try repository.libraryFirstAidReport()
        XCTAssertEqual(report.missingManagedOriginals.map(\.id), [missing.id])
        XCTAssertTrue(report.untrackedManagedFiles.isEmpty)
        XCTAssertFalse(files.fileExists(atPath: originals.path))

        try files.createSymbolicLink(at: originals, withDestinationURL: folder)
        XCTAssertThrowsError(try repository.libraryFirstAidReport()) {
            guard case LibraryError.unsafePath = $0 else { return XCTFail("Unexpected scan error: \($0)") }
        }
    }

    func testManagedNamesFollowTheVolumesCaseSensitivity() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let tracked = photo("Portrait.png")
        let actual = try repository.managedOriginalURL("PORTRAIT.png")
        try Data([1]).write(to: actual)
        var library = Library()
        library.photos = [tracked]
        try repository.save(library)

        let report = try repository.libraryFirstAidReport()
        let trackedPath = actual.deletingLastPathComponent().appendingPathComponent(tracked.filename)
        let trackedPathExists = FileManager.default.fileExists(atPath: trackedPath.path)
        XCTAssertEqual(report.missingManagedOriginals.map(\.id), trackedPathExists ? [] : [tracked.id])
        XCTAssertEqual(report.untrackedManagedFiles, trackedPathExists ? [] : [actual.lastPathComponent])
    }

    func testRecoveryVerifiesFingerprintsAndUsesOnlyReviewedOriginals() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let search = folder.appendingPathComponent("Search")
        try FileManager.default.createDirectory(at: search, withIntermediateDirectories: false)
        let managed = try recoveryPhoto("Managed.png", byte: 1, in: search)
        let wrongManaged = try recoveryPhoto("Wrong managed.png", byte: 2, in: search)
        var offline = try recoveryPhoto("Offline.png", byte: 3, in: search)
        offline.referencedPath = folder.appendingPathComponent("Disconnected/Offline.png").path
        offline.trashedAt = Date()
        var wrongReference = try recoveryPhoto("Wrong reference.png", byte: 4, in: search)
        wrongReference.referencedPath = folder.appendingPathComponent("Disconnected/Wrong reference.png").path
        let present = try recoveryPhoto("Present.png", byte: 5, in: search)
        let presentURL = try repository.managedOriginalURL(present.filename)
        try Data([5]).write(to: presentURL)
        let untracked = try repository.managedOriginalURL("Untracked.png")
        try Data([6]).write(to: untracked)
        try Data([7]).write(to: search.appendingPathComponent(wrongManaged.originalName))
        try Data([8]).write(to: search.appendingPathComponent(wrongReference.originalName))
        var library = Library()
        library.photos = [managed, wrongManaged, offline, wrongReference, present]
        XCTAssertNotNil(library.createVersion(of: managed.id, from: .current))
        try repository.save(library)
        let before = try Data(contentsOf: repository.root.appendingPathComponent("catalog.json"))
        let review = try repository.libraryFirstAidReport()
        // This new missing file was not part of the reviewed scope.
        try FileManager.default.removeItem(at: presentURL)

        let restored = try repository.recoverMissingManagedOriginals(in: search, after: review)
        XCTAssertEqual(restored.restored, [managed.originalName])
        XCTAssertEqual(restored.unmatched, [wrongManaged.originalName])
        XCTAssertEqual(try Data(contentsOf: repository.root.appendingPathComponent("catalog.json")), before)
        XCTAssertEqual(try LibraryRepository.digest(repository.availableOriginalURL(managed)), managed.sha256)
        XCTAssertThrowsError(try repository.availableOriginalURL(wrongManaged))
        XCTAssertThrowsError(try repository.availableOriginalURL(present))

        let reconnected = try repository.reconnectOfflineReferences(in: search, after: review)
        XCTAssertEqual(reconnected.report.reconnected, [offline.originalName])
        XCTAssertEqual(reconnected.report.unmatched, [wrongReference.originalName])
        library.photos[2].referencedPath = search.appendingPathComponent(offline.originalName).path
        XCTAssertEqual(try repository.load().photos, library.photos)
        XCTAssertEqual(reconnected.library.photos, library.photos)
        XCTAssertEqual(try Data(contentsOf: untracked), Data([6]))
        let after = try repository.libraryFirstAidReport()
        XCTAssertEqual(after.missingManagedOriginals.map(\.id), [wrongManaged.id, present.id])
        XCTAssertEqual(after.offlineReferences.map(\.id), [wrongReference.id])
    }

    func testRecoveryRejectsStaleCatalogueBeforeSearchAndAtPublication() throws {
        let (folder, repository) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let search = folder.appendingPathComponent("Search")
        try FileManager.default.createDirectory(at: search, withIntermediateDirectories: false)
        let managed = try recoveryPhoto("Managed.png", byte: 1, in: search)
        var offline = try recoveryPhoto("Offline.png", byte: 2, in: search)
        offline.referencedPath = folder.appendingPathComponent("Disconnected/Offline.png").path
        var library = Library()
        library.version = 2
        library.photos = [managed, offline]
        try repository.save(library)
        let review = try repository.libraryFirstAidReport()
        var changed = library
        changed.photos[0].caption = "New catalogue edit"
        try repository.save(changed)
        let current = try Data(contentsOf: repository.root.appendingPathComponent("catalog.json"))

        XCTAssertThrowsError(try repository.recoverMissingManagedOriginals(in: search, after: review)) { verifyStale($0) }
        XCTAssertThrowsError(try repository.reconnectOfflineReferences(in: search, after: review)) { verifyStale($0) }

        // Exercise the publication guard with the stale snapshot the search started with.
        XCTAssertThrowsError(try repository.recoverMissingManagedOriginals(in: search, library: library,
                                                                             originalIDs: [managed.id],
                                                                             expectedCatalogue: review.catalogue)) { verifyStale($0) }
        XCTAssertThrowsError(try repository.reconnectMissingReferences(in: search, library: &library,
                                                                         originalIDs: [offline.id], includeTrashed: true,
                                                                         expectedCatalogue: review.catalogue)) { verifyStale($0) }
        XCTAssertEqual(try Data(contentsOf: repository.root.appendingPathComponent("catalog.json")), current)
        XCTAssertEqual(try repository.load().photos, changed.photos)
        XCTAssertThrowsError(try repository.availableOriginalURL(managed))
    }

    private func verifyStale(_ error: Error) {
        guard case LibraryError.integrity(let message) = error else { return XCTFail("Unexpected error: \(error)") }
        XCTAssertTrue(message.contains("catalogue changed"))
    }

    private func recoveryPhoto(_ name: String, byte: UInt8, in folder: URL) throws -> Photo {
        let source = folder.appendingPathComponent(name)
        try Data([byte]).write(to: source)
        return Photo(filename: name, originalName: name, projectID: nil, width: 8, height: 6,
                     camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
    }

    private func fixture() throws -> (URL, LibraryRepository) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueFirstAid-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        return (folder, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library")))
    }

    private func photo(_ filename: String) -> Photo {
        Photo(filename: filename, originalName: filename, projectID: nil, width: 8, height: 6,
              camera: "", captureDate: "", sha256: "fixture")
    }
}
