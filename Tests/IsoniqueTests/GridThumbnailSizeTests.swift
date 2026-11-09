import XCTest
import IsoniqueCore
@testable import Isonique

final class GridThumbnailSizeTests: XCTestCase {
    @MainActor
    func testSizePersistsAcrossLibrariesIndependentlyOfLayout() throws {
        let suite = "IsoniqueGridSize-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let first = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("First")).root
        let second = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Second")).root
        let workspace = Workspace(libraryRoot: first, preferences: preferences)

        XCTAssertEqual(workspace.gridThumbnailSize, .standard)
        workspace.setBrowserLayout(.list)
        let catalogue = first.appendingPathComponent("catalog.json")
        let before = try Data(contentsOf: catalogue)
        workspace.gridThumbnailSize = .large
        XCTAssertEqual(workspace.browserLayout, .list)
        XCTAssertEqual(try Data(contentsOf: catalogue), before)

        let reopened = Workspace(libraryRoot: second, preferences: preferences)
        XCTAssertEqual(reopened.gridThumbnailSize, .large)
        XCTAssertEqual(reopened.browserLayout, .list)
        reopened.gridThumbnailSize = .compact
        XCTAssertEqual(Workspace(libraryRoot: first, preferences: preferences).gridThumbnailSize, .compact)

        preferences.set("unknown", forKey: GridThumbnailSize.preferenceKey)
        XCTAssertEqual(Workspace(libraryRoot: first, preferences: preferences).gridThumbnailSize, .standard)
    }
}
