import XCTest
import IsoniqueCore
@testable import Isonique

final class RecentLibraryTests: XCTestCase {
    @MainActor
    func testVerifiedSwitchPersistsRecentsAndFailedOpenKeepsActiveLibrary() async throws {
        let (root, preferences) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parentA = root.appendingPathComponent("A")
        let parentB = root.appendingPathComponent("B")
        for parent in [parentA, parentB] {
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        }
        let first = try LibraryRepository.createEmpty(at: parentA.appendingPathComponent("Photos"))
        let second = try LibraryRepository.createEmpty(at: parentB.appendingPathComponent("Photos"))
        var library = Library()
        library.projects = [Collection(name: "Second Library")]
        try second.save(library)
        let workspace = Workspace(libraryRoot: first.root, preferences: preferences)
        workspace.search = "old search"

        await workspace.openLibrary(at: second.root)

        XCTAssertEqual(workspace.repository?.root, second.root)
        XCTAssertEqual(workspace.library.projects.map(\.name), ["Second Library"])
        XCTAssertEqual(workspace.search, "")
        XCTAssertEqual(workspace.recentLibraryPaths, [second.root.path, first.root.path])
        XCTAssertTrue(workspace.recentLibraryTitle(for: first.root.path).hasSuffix(parentA.path))
        XCTAssertTrue(workspace.recentLibraryTitle(for: second.root.path).hasSuffix(parentB.path))

        let missing = root.appendingPathComponent("Missing")
        await workspace.openLibrary(at: missing)

        XCTAssertNotNil(workspace.error)
        XCTAssertEqual(workspace.repository?.root, second.root)
        XCTAssertEqual(workspace.recentLibraryPaths, [second.root.path, first.root.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))

        let reopened = Workspace(preferences: preferences)
        XCTAssertEqual(reopened.repository?.root, second.root)
        XCTAssertEqual(reopened.recentLibraryPaths, [second.root.path, first.root.path])
        await reopened.openLibrary(at: first.root)
        XCTAssertEqual(reopened.recentLibraryPaths, [first.root.path, second.root.path])
        reopened.recentLibraryPaths = []
        let cleared = Workspace(preferences: preferences)
        XCTAssertEqual(cleared.repository?.root, first.root)
        XCTAssertTrue(cleared.recentLibraryPaths.isEmpty)
    }

    @MainActor
    func testRecentListDropsDuplicatesAndCapsStoredPaths() throws {
        let (root, preferences) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Current"))
        let paths = (0...12).map { root.appendingPathComponent("Library \($0)").path }
        preferences.set(["relative", paths[0]] + paths, forKey: Workspace.recentLibraryKey)

        let workspace = Workspace(libraryRoot: library.root, preferences: preferences)

        XCTAssertEqual(workspace.recentLibraryPaths, Array(paths.prefix(10)))
    }

    private func fixture() throws -> (URL, UserDefaults) {
        let token = "IsoniqueRecentTests-\(UUID().uuidString)"
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(token)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: token))
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: token) }
        return (root, preferences)
    }
}
