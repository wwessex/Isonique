import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor
final class PeopleWorkflowTests: XCTestCase {
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
        reopened.showPeople()
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
