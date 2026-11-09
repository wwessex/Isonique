import XCTest
@testable import IsoniqueCore

final class OriginalRelocationTests: XCTestCase {
    func testRelocationSavesAllVersionsBeforeRemovingManagedCopies() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let first = try managed("Portrait.png", filename: "first.png", bytes: [1], in: repo)
        let second = try managed("Portrait.png", filename: "second.png", bytes: [2], in: repo)
        let occupied = try managed("Occupied.png", filename: "third.png", bytes: [3], in: repo)
        let unrelated = try managed("Unrelated.png", filename: "fourth.png", bytes: [4], in: repo)
        try Data([9]).write(to: fixture.target.appendingPathComponent("Occupied.png"))
        try FileManager.default.createDirectory(at: fixture.target.appendingPathComponent("third.png"),
                                                withIntermediateDirectories: false)
        var library = Library()
        library.photos = [first, second, occupied, unrelated]
        let version = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        library.photos[4].trashedAt = Date()
        library.photos[4].adjustments.exposure = 0.6
        try repo.save(library)

        var released: [String] = []
        let report = try repo.relocateOriginals([first.id, second.id, occupied.id], to: fixture.target, in: &library) { source in
            let saved = try repo.load()
            XCTAssertNotNil(saved.photos[0].referencedPath)
            XCTAssertEqual(saved.photos[0].referencedPath, saved.photos[4].referencedPath)
            XCTAssertNotNil(saved.photos[1].referencedPath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
            try FileManager.default.moveItem(at: source, to: fixture.trash.appendingPathComponent(source.lastPathComponent))
            released.append(source.lastPathComponent)
        }

        XCTAssertEqual(report.relocated, ["Portrait.png", "Portrait.png"])
        XCTAssertEqual(report.renamed, ["second.png"])
        XCTAssertEqual(report.occupied, ["Occupied.png"])
        XCTAssertTrue(report.retained.isEmpty)
        XCTAssertEqual(released, ["first.png", "second.png"])
        let saved = try LibraryRepository(root: repo.root).load()
        XCTAssertEqual(saved.photos, library.photos)
        XCTAssertEqual(saved.photos[4].id, version.id)
        XCTAssertEqual(saved.photos[4].adjustments.exposure, 0.6)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(saved.photos[4])), Data([1]))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(saved.photos[1])), Data([2]))
        XCTAssertEqual(try Data(contentsOf: fixture.target.appendingPathComponent("Occupied.png")), Data([9]))
        XCTAssertNil(saved.photos[2].referencedPath)
        XCTAssertNil(saved.photos[3].referencedPath)
        XCTAssertEqual(try LibraryBackup.verify(repo), 4)
    }

    func testFailedSaveKeepsManagedOriginalAndRetryReusesExactDestination() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let photo = try managed("Photo.png", filename: "storage.png", bytes: [7], in: repo)
        var library = Library()
        library.photos = [photo]
        try repo.save(library)
        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        try FileManager.default.setAttributes([.immutable: true], ofItemAtPath: catalogue.path)
        defer { try? FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path) }
        XCTAssertThrowsError(try repo.relocateOriginals([photo.id], to: fixture.target, in: &library) { _ in
            XCTFail("An unsaved relocation must never release the source")
        })
        try FileManager.default.setAttributes([.immutable: false], ofItemAtPath: catalogue.path)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertEqual(library.photos, [photo])
        let managedPath = try repo.availableOriginalURL(photo)
        XCTAssertEqual(try Data(contentsOf: managedPath), Data([7]))
        let destination = fixture.target.appendingPathComponent("Photo.png")
        let fileID = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber)

        let report = try repo.relocateOriginals([photo.id], to: fixture.target, in: &library) { _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        XCTAssertEqual(report.relocated, ["Photo.png"])
        XCTAssertEqual(report.retained, ["Photo.png"])
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: destination.path)[.systemFileNumber] as? NSNumber, fileID)
        let saved = try repo.load()
        XCTAssertEqual(saved.version, 2)
        XCTAssertNotNil(saved.photos[0].referencedPath)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(saved.photos[0])), Data([7]))
        XCTAssertEqual(try Data(contentsOf: managedPath), Data([7]))
    }

    func testCancellationAndUnsafeDestinationPreserveManagedOriginal() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let photo = try managed("Photo.png", filename: "storage.png", bytes: [8], in: repo)
        var library = Library()
        library.photos = [photo]
        try repo.save(library)
        let inside = repo.root.appendingPathComponent("Originals")
        XCTAssertThrowsError(try repo.relocateOriginals([photo.id], to: inside, in: &library) { _ in XCTFail() })
        let saved = library
        let target = fixture.target
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            var draft = saved
            return try repo.relocateOriginals([photo.id], to: target, in: &draft) { _ in XCTFail() }
        }
        do {
            _ = try await cancelled.value
            XCTFail("Expected cancellation before copying")
        } catch is CancellationError {}
        XCTAssertEqual(try repo.load().photos, [photo])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(photo)), Data([8]))
    }

    func testRelocatingReferencesKeepsAliasedSourceAndSkipsCurrentFolder() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let sharedSource = fixture.folder.appendingPathComponent("Shared.png")
        let alias = fixture.folder.appendingPathComponent("Alias.png")
        let independentSource = fixture.folder.appendingPathComponent("Independent.png")
        let currentSource = fixture.target.appendingPathComponent("Current.png")
        try Data([1]).write(to: sharedSource)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: sharedSource)
        try Data([2]).write(to: independentSource)
        try Data([3]).write(to: currentSource)
        let shared = try reference("Renamed version.png", filename: "one.png", source: sharedSource)
        var other = try reference("Unselected.jpg", filename: "two.png", source: alias)
        other.trashedAt = Date()
        let independent = try reference("Independent.png", filename: "three.png", source: independentSource)
        let current = try reference("Current.png", filename: "four.png", source: currentSource)
        var library = Library()
        library.version = 2
        library.photos = [shared, other, independent, current]
        try repo.save(library)

        var released: [String] = []
        let report = try repo.relocateOriginals([shared.id, independent.id, current.id], to: fixture.target,
                                               in: &library, keepReferencedSources: false) { source in
            try FileManager.default.moveItem(at: source, to: fixture.trash.appendingPathComponent(source.lastPathComponent))
            released.append(source.lastPathComponent)
        }

        XCTAssertEqual(report.relocated, ["Renamed version.png", "Independent.png"])
        XCTAssertEqual(report.retained, ["Renamed version.png"])
        XCTAssertEqual(report.alreadyInFolder, ["Current.png"])
        XCTAssertEqual(released, ["Independent.png"])
        let saved = try repo.load()
        XCTAssertEqual(saved.photos[0].referencedPath, fixture.target.appendingPathComponent("Shared.png").path)
        XCTAssertEqual(saved.photos[2].referencedPath, fixture.target.appendingPathComponent("Independent.png").path)
        XCTAssertEqual(saved.photos[1], other)
        XCTAssertEqual(saved.photos[3], current)
        XCTAssertEqual(try Data(contentsOf: sharedSource), Data([1]))
        XCTAssertEqual(try Data(contentsOf: alias), Data([1]))
        XCTAssertEqual(try LibraryBackup.verify(repo), 4)
    }

    func testKeepingPreviousExternalCopiesIsDefault() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let source = fixture.folder.appendingPathComponent("Original.png")
        try Data([8]).write(to: source)
        let photo = try reference("Original.png", filename: "storage.png", source: source)
        var library = Library()
        library.version = 2
        library.photos = [photo]
        try repo.save(library)
        let report = try repo.relocateOriginals([photo.id], to: fixture.target, in: &library) { _ in
            XCTFail("The previous referenced file should stay in place")
        }
        XCTAssertEqual(report.retained, ["Original.png"])
        XCTAssertEqual(try Data(contentsOf: source), Data([8]))
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(library.photos[0])), Data([8]))
        XCTAssertEqual(try repo.load().photos, library.photos)
    }

    func testProjectAndCataloguePresetsPreviewOnePathForAllVersions() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let project = Collection(name: "Paris / Editorial: 2026")
        var original = try managed("Client-001.NEF", filename: "stored.nef", bytes: [25], in: repo)
        original.sourceName = "DSC_0001.NEF"
        original.projectID = project.id
        var library = try repo.load()
        library.projects = [project]
        library.photos = [original]
        let version = try XCTUnwrap(library.createVersion(of: original.id, from: .current))
        library.photos[1].trashedAt = Date()
        library.photos[1].adjustments.exposure = 0.8
        library = try repo.save(library)
        let catalogue = repo.root.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)

        let review = try repo.previewRelocatingOriginals([version.originalID, original.originalID], to: fixture.target,
                                                        in: library, options: .init(filename: .catalogue, subfolders: .project))
        let row = try XCTUnwrap(review.items.first)
        let relative = "Paris - Editorial- 2026/Client-001.NEF"
        XCTAssertEqual(review.items.count, 1)
        XCTAssertEqual(review.relocationCount, 1)
        XCTAssertEqual(row.versionCount, 2)
        XCTAssertEqual(row.preferredPath, relative)
        XCTAssertEqual(row.destinationPath, relative)
        XCTAssertEqual(row.disposition, .copy)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: fixture.target.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)
        XCTAssertEqual(try Data(contentsOf: repo.availableOriginalURL(original)), Data([25]))

        var released = 0
        let result = try repo.relocateOriginals(after: review, in: &library) { source in
            let saved = try repo.load()
            let destination = fixture.target.appendingPathComponent(relative)
            XCTAssertEqual(saved.photos.map(\.referencedPath), [destination.path, destination.path])
            XCTAssertEqual(try Data(contentsOf: destination), Data([25]))
            try FileManager.default.moveItem(at: source, to: fixture.trash.appendingPathComponent(source.lastPathComponent))
            released += 1
        }
        XCTAssertEqual(released, 1)
        XCTAssertEqual(result.relocated, ["Client-001.NEF"])
        let reopened = try repo.load()
        XCTAssertEqual(reopened.photos[1].id, version.id)
        XCTAssertNotNil(reopened.photos[1].trashedAt)
        XCTAssertEqual(reopened.photos[1].adjustments.exposure, 0.8)
        XCTAssertTrue(library.hasSameCatalogueRevision(as: reopened))
    }

    func testNumberedFilenamesUseCaptureMonthAndUnknownDateFolders() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        var first = try managed("A.CR3", filename: "first.cr3", bytes: [1], in: repo)
        first.captureDate = "2024:02:29 22:18:07"
        var second = try managed("B.NEF", filename: "second.nef", bytes: [2], in: repo)
        second.captureDate = "2023:02:29 00:00:00"
        let third = try managed("C", filename: "third", bytes: [3], in: repo)
        var library = try repo.load()
        library.photos = [first, second, third]
        library = try repo.save(library)

        let review = try repo.previewRelocatingOriginals([third.id, second.id, first.id], to: fixture.target, in: library,
                                                         options: .init(filename: .sequence, subfolders: .captureMonth))
        let expected = ["2024/02/Original-0001.cr3", "Unknown Capture Date/Original-0002.nef",
                        "Unknown Capture Date/Original-0003"]
        XCTAssertEqual(review.items.compactMap(\.destinationPath), expected)
        let report = try repo.relocateOriginals(after: review, in: &library) { _ in }
        XCTAssertEqual(report.relocated, ["A.CR3", "B.NEF", "C"])
        XCTAssertEqual(library.photos.compactMap(\.referencedPath), expected.map { fixture.target.appendingPathComponent($0).path })
        for (index, relative) in expected.enumerated() {
            XCTAssertEqual(try Data(contentsOf: fixture.target.appendingPathComponent(relative)), Data([UInt8(index + 1)]))
        }
    }

    func testPreviewReportsFallbackReuseAndBlockedNames() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let first = try managed("Portrait.png", filename: "first.png", bytes: [1], in: repo)
        let second = try managed("portrait.PNG", filename: "second.png", bytes: [2], in: repo)
        let third = try managed("Occupied.png", filename: "third.png", bytes: [3], in: repo)
        let fourth = try managed("Blocked.png", filename: "fourth.png", bytes: [4], in: repo)
        let files = FileManager.default
        let paths = ["Occupied.png": Data([9]), "third.png": Data([3]), "Blocked.png": Data([9]), "fourth.png": Data([9])]
        for (name, bytes) in paths { try bytes.write(to: fixture.target.appendingPathComponent(name)) }
        let reused = fixture.target.appendingPathComponent("third.png")
        let inode = try files.attributesOfItem(atPath: reused.path)[.systemFileNumber] as? NSNumber
        var library = try repo.load()
        library.photos = [first, second, third, fourth]
        library = try repo.save(library)

        let preview = try repo.previewRelocatingOriginals(Set(library.photos.map(\.id)), to: fixture.target, in: library)
        XCTAssertEqual(preview.items.map(\.disposition), [.copy, .copy, .reuse, .occupied])
        XCTAssertEqual(preview.items.map(\.destinationPath), ["Portrait.png", "second.png", "third.png", nil])
        XCTAssertEqual(preview.items[1].preferredPath, "portrait.PNG")
        XCTAssertEqual(preview.relocationCount, 3)
        XCTAssertEqual(Set(try files.contentsOfDirectory(atPath: fixture.target.path)), Set(paths.keys))

        let report = try repo.relocateOriginals(after: preview, in: &library) { _ in }
        XCTAssertEqual(report.renamed, ["second.png", "third.png"])
        XCTAssertEqual(report.occupied, ["Blocked.png"])
        XCTAssertNil(library.photos[3].referencedPath)
        XCTAssertEqual(try files.attributesOfItem(atPath: reused.path)[.systemFileNumber] as? NSNumber, inode)
        for (name, bytes) in paths { XCTAssertEqual(try Data(contentsOf: fixture.target.appendingPathComponent(name)), bytes) }
    }

    func testChangedDestinationAndSymlinkNeverChooseAnUnreviewedPath() throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.folder) }
        let repo = fixture.repo
        let project = Collection(name: "Shoot")
        let first = try managed("Late.png", filename: "first.png", bytes: [1], in: repo)
        var second = try managed("Linked.png", filename: "second.png", bytes: [2], in: repo)
        second.projectID = project.id
        var library = try repo.load()
        library.projects = [project]
        library.photos = [first, second]
        library = try repo.save(library)
        let review = try repo.previewRelocatingOriginals([first.id, second.id], to: fixture.target, in: library,
                                                        options: .init(subfolders: .project))
        XCTAssertEqual(review.items.compactMap(\.destinationPath), ["Unassigned/Late.png", "Shoot/Linked.png"])
        let files = FileManager.default
        let lateFolder = fixture.target.appendingPathComponent("Unassigned")
        try files.createDirectory(at: lateFolder, withIntermediateDirectories: false)
        let late = lateFolder.appendingPathComponent("Late.png")
        try Data([9]).write(to: late)
        try files.createSymbolicLink(at: fixture.target.appendingPathComponent("Shoot"), withDestinationURL: fixture.trash)

        let report = try repo.relocateOriginals(after: review, in: &library) { _ in XCTFail("No source can be released") }
        XCTAssertTrue(report.relocated.isEmpty)
        XCTAssertEqual(report.occupied, ["Unassigned/Late.png"])
        XCTAssertEqual(report.failed, ["Shoot/Linked.png"])
        XCTAssertEqual(try Data(contentsOf: late), Data([9]))
        XCTAssertEqual(try files.contentsOfDirectory(atPath: lateFolder.path), ["Late.png"])
        XCTAssertTrue(try files.contentsOfDirectory(atPath: fixture.trash.path).isEmpty)
        XCTAssertEqual(try repo.load().photos, [first, second])

        let refreshed = try repo.previewRelocatingOriginals([first.id, second.id], to: fixture.target, in: library,
                                                           options: .init(subfolders: .project))
        XCTAssertEqual(refreshed.items.map(\.destinationPath), ["Unassigned/first.png", nil])
        let other = try LibraryRepository(root: repo.root)
        var latest = try other.load()
        latest.photos[0].caption = "Edited after preview"
        try other.save(latest)
        XCTAssertThrowsError(try repo.relocateOriginals(after: refreshed, in: &library) { _ in XCTFail() })
        XCTAssertEqual(try files.contentsOfDirectory(atPath: lateFolder.path), ["Late.png"])
        XCTAssertEqual(try repo.load().photos.first?.caption, "Edited after preview")
    }

    private func reference(_ name: String, filename: String, source: URL) throws -> Photo {
        var photo = Photo(filename: filename, originalName: name, projectID: nil, width: 8, height: 8,
                          camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
        photo.referencedPath = source.path
        return photo
    }

    private func fixture() throws -> (folder: URL, repo: LibraryRepository, target: URL, trash: URL) {
        let folder = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueRelocation-\(UUID().uuidString)")
        let target = folder.appendingPathComponent("Destination")
        let trash = folder.appendingPathComponent("Test Trash")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: false)
        return (folder, try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library")), target, trash)
    }

    private func managed(_ name: String, filename: String, bytes: [UInt8], in repo: LibraryRepository) throws -> Photo {
        let source = try repo.managedOriginalURL(filename)
        try Data(bytes).write(to: source)
        return Photo(filename: filename, originalName: name, projectID: nil, width: 8, height: 8,
                     camera: "", captureDate: "", sha256: try LibraryRepository.digest(source))
    }
}
