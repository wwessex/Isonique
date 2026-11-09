import XCTest
@testable import IsoniqueCore

final class ProjectAlbumMergeTests: XCTestCase {
    func testMergesNamesAndCompleteRulesUnderEitherPreference() async throws {
        for preference in [ProjectMergePreference.current, .incoming] {
            let fixture = try fixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            var current = try fixture.destination.load()
            var incoming = try fixture.source.load()
            try fixture.edit(.regular, in: &current) { $0.name = "Current Selects" }
            try fixture.edit(.regular, in: &incoming) { $0.name = "Imported Selects" }
            try fixture.edit(.independent, in: &current) { $0.name = "Current Smart Album Name" }
            var query = PhotoQuery()
            query.match = .any
            query.criteria = [
                PhotoQueryCriterion(field: .rating, comparison: .minimum, value: "4"),
                PhotoQueryCriterion(field: .flag, comparison: .equals, value: "true")
            ]
            try fixture.edit(.independent, in: &incoming) { $0.rule?.query = query }
            try fixture.edit(.competing, in: &current) {
                $0.name = "Agreed Name"
                $0.rule?.minimumRating = 4
            }
            try fixture.edit(.competing, in: &incoming) {
                $0.name = "Agreed Name"
                $0.rule?.flaggedOnly = true
            }
            try fixture.destination.save(current)
            try fixture.source.save(incoming)
            let sourceURL = fixture.source.root.appendingPathComponent("catalog.json")
            let sourceBefore = try Data(contentsOf: sourceURL)

            let prefersImported = preference == .incoming
            let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: preference, review: {
                XCTAssertEqual($0.albumUpdates, prefersImported ? 3 : 1)
                XCTAssertEqual($0.albumConflicts.map(\.albumName), ["Current Selects", "Agreed Name"])
                XCTAssertEqual($0.albumConflicts.map(\.fields), [["Name"], ["Smart Album Rules"]])
                XCTAssertEqual($0.updated, 0)
                return true
            })

            let (_, saved) = try LibraryBackup.openVerified(fixture.destination.root)
            XCTAssertEqual(result.albumUpdates, prefersImported ? 3 : 1)
            XCTAssertEqual(result.conflicts, 2)
            XCTAssertEqual(try fixture.album(.regular, in: saved).name, prefersImported ? "Imported Selects" : "Current Selects")
            let independent = try fixture.album(.independent, in: saved)
            XCTAssertEqual(independent.name, "Current Smart Album Name")
            XCTAssertEqual(independent.rule?.query, query)
            XCTAssertEqual(saved.photos.filter { independent.rule?.includes($0) == true }.map(\.originalName), ["Select.png"])
            let competing = try fixture.album(.competing, in: saved)
            XCTAssertEqual(competing.name, "Agreed Name")
            XCTAssertEqual(competing.rule?.minimumRating, prefersImported ? 0 : 4)
            XCTAssertEqual(competing.rule?.flaggedOnly, prefersImported)
            XCTAssertEqual(saved.photos, current.photos)
            XCTAssertEqual(try Data(contentsOf: sourceURL), sourceBefore)
        }
    }

    func testProtectsSharedAlbumsAndSmartAlbumScope() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var current = try fixture.destination.load()
        var incoming = try fixture.source.load()
        let exported = try XCTUnwrap(incoming.projectExportMembership?.albumDefinitions)
        XCTAssertEqual(Set(exported.map(\.id)), Set([Album.regular, .independent, .competing, .sharedLater, .scoped]
            .compactMap { fixture.ids[$0] }))

        // The first album was shared at export. The second is now shared with a photo in Library Trash.
        let outside = try XCTUnwrap(current.photos.firstIndex { $0.originalName == "Outside.png" })
        current.photos[outside].albumIDs = [try XCTUnwrap(fixture.ids[.sharedLater])]
        current.photos[outside].trashedAt = Date()
        for key in [Album.sharedAtExport, .sharedLater, .global, .scoped] {
            try fixture.edit(key, in: &incoming) { $0.name = "Imported \(key.rawValue)" }
        }
        try fixture.edit(.global, in: &incoming) { $0.rule?.projectID = fixture.projectID }
        try fixture.edit(.scoped, in: &incoming) { $0.rule?.projectID = nil }
        try fixture.destination.save(current)
        try fixture.source.save(incoming)

        let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .incoming, review: {
            XCTAssertEqual($0.albumUpdates, 0)
            XCTAssertTrue($0.albumConflicts.isEmpty)
            return true
        })

        let (_, saved) = try LibraryBackup.openVerified(fixture.destination.root)
        XCTAssertEqual(result.albumUpdates, 0)
        XCTAssertEqual(saved.albums, current.albums)
        XCTAssertEqual(saved.photos, current.photos)
    }

    func testOlderExportKeepsMatchingDefinitionsAndStillAddsNewAlbums() async throws {
        let fixture = try fixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let current = try fixture.destination.load()
        var incoming = try fixture.source.load()
        try fixture.edit(.regular, in: &incoming) { $0.name = "Imported Selects" }
        try fixture.edit(.independent, in: &incoming) { $0.rule?.flaggedOnly = true }
        let added = Collection(name: "New imported album")
        incoming.albums.append(added)
        try fixture.source.save(incoming)

        let url = fixture.source.root.appendingPathComponent("catalog.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var membership = try XCTUnwrap(json["projectExportMembership"] as? [String: Any])
        membership.removeValue(forKey: "albumDefinitions")
        json["projectExportMembership"] = membership
        try JSONSerialization.data(withJSONObject: json).write(to: url)
        XCTAssertNil(try fixture.source.load().projectExportMembership?.albumDefinitions)

        let result = try await fixture.destination.mergeProjectLibrary(from: fixture.source.root, prefer: .incoming, review: {
            XCTAssertEqual($0.addedAlbums, 1)
            XCTAssertEqual($0.albumUpdates, 0)
            XCTAssertTrue($0.albumConflicts.isEmpty)
            return true
        })

        let (_, saved) = try LibraryBackup.openVerified(fixture.destination.root)
        XCTAssertEqual(result.albumUpdates, 0)
        XCTAssertEqual(saved.albums, current.albums + [added])
    }

    private enum Album: String, CaseIterable {
        case regular = "Selects"
        case independent = "Independent edits"
        case competing = "Competing rules"
        case sharedAtExport = "Shared at export"
        case sharedLater = "Shared later"
        case global = "Global Smart Album"
        case scoped = "Project Smart Album"
    }

    private struct Fixture {
        let root: URL
        let destination: LibraryRepository
        let source: LibraryRepository
        let projectID: UUID
        let ids: [Album: UUID]

        func album(_ key: Album, in library: Library) throws -> Collection {
            try XCTUnwrap(library.albums.first { $0.id == ids[key] })
        }

        func edit(_ key: Album, in library: inout Library, change: (inout Collection) -> Void) throws {
            let index = try XCTUnwrap(library.albums.firstIndex { $0.id == ids[key] })
            change(&library.albums[index])
        }
    }

    private func fixture() throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("IsoniqueAlbumMerge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let destination = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Destination"))
        let project = Collection(name: "Shoot")
        let other = Collection(name: "Other Project")
        var library = Library()
        library.version = 2
        library.projects = [project, other]
        var ids: [Album: UUID] = [:]
        for key in Album.allCases {
            var album = Collection(name: key.rawValue)
            switch key {
            case .independent, .competing, .scoped:
                album.rule = SmartAlbumRule()
                album.rule?.projectID = project.id
            case .global:
                album.rule = SmartAlbumRule()
            default: break
            }
            ids[key] = album.id
            library.albums.append(album)
        }
        for (index, name) in ["Select.png", "Other.png", "Outside.png"].enumerated() {
            let url = try destination.managedOriginalURL(name)
            try Data([UInt8(index)]).write(to: url)
            var photo = Photo(filename: name, originalName: name, projectID: index == 2 ? other.id : project.id,
                              width: 8, height: 6, camera: "", captureDate: "", sha256: try LibraryRepository.digest(url))
            photo.rating = index == 0 ? 5 : 1
            if index == 0 {
                photo.albumIDs = Set([Album.regular, .sharedAtExport, .sharedLater].compactMap { ids[$0] })
            }
            if index == 2 { photo.albumIDs = [try XCTUnwrap(ids[.sharedAtExport])] }
            library.photos.append(photo)
        }
        try destination.save(library)
        let folder = root.appendingPathComponent("Exported")
        try LibraryBackup.exportProject(project.id, from: destination, to: folder)
        let (source, _) = try LibraryBackup.openVerified(folder)
        return Fixture(root: root, destination: destination, source: source, projectID: project.id, ids: ids)
    }
}
