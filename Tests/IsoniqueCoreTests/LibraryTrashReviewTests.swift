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
