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

        let preview = try fixture.destination.previewLibraryMerge(from: fixture.source.root)

        XCTAssertEqual(preview.reusableOriginals, 0)
        XCTAssertEqual(preview.conflicts.count, 2)
        XCTAssertTrue(preview.conflicts.contains { $0.hasPrefix("Album identity —") })
        XCTAssertTrue(preview.conflicts.contains { $0.hasPrefix("Original fingerprint —") })
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

    private struct Fixture {
        let root: URL
        let destination: LibraryRepository
        let source: LibraryRepository
        let sharedPhoto: Photo
        let localOnly: Photo
        let reusedVersion: Photo
        let incomingPhoto: Photo
        let incomingVersion: Photo
        let unassigned: Photo
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
        let unassigned = try photo("Unassigned.png", byte: 4, project: nil, in: source)
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
        try source.save(incoming)
        return Fixture(root: root, destination: destination, source: source, sharedPhoto: sharedPhoto, localOnly: localOnly,
                       reusedVersion: reused, incomingPhoto: incomingPhoto, incomingVersion: version, unassigned: unassigned)
    }

    private func photo(_ name: String, byte: UInt8, project: UUID?, in repository: LibraryRepository) throws -> Photo {
        let url = try repository.managedOriginalURL(name)
        try Data([byte]).write(to: url)
        return Photo(filename: name, originalName: name, projectID: project, width: 8, height: 6,
                     camera: "", captureDate: "", sha256: try LibraryRepository.digest(url))
    }
}
