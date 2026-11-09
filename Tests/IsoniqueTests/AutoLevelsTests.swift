import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class AutoLevelsTests: XCTestCase {
    @MainActor
    func testAutomaticAndQuarterToneRecipesPersistWithUndo() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueAutoLevels-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder)
        let suite = "IsoniqueAutoLevelsTests.\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        var photo = Photo(filename: "levels.png", originalName: "levels.png", projectID: nil,
                          width: 8, height: 8, camera: "", captureDate: "", sha256: "fixture")
        photo.adjustments.gamma = 1.5
        var library = workspace.library
        library.photos = [photo]
        XCTAssertTrue(workspace.commit(library))
        workspace.selection = photo.id
        var histogram = ToneHistogram()
        histogram.luminance[32] = 50; histogram.luminance[192] = 50
        histogram.red[20] = 50; histogram.red[200] = 50
        histogram.green[50] = 100
        histogram.blue[30] = 50; histogram.blue[180] = 50
        workspace.applyAutoLevels(.combined, input: histogram, for: photo, blackClip: 0, whiteClip: 0)
        let combined = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(combined.adjustments.blackPoint, 32.0 / 255)
        XCTAssertEqual(combined.adjustments.whitePoint, 192.0 / 255)
        XCTAssertEqual(combined.adjustments.gamma, 1.5)
        XCTAssertNil(combined.adjustments.channelLevels)
        workspace.applyAutoLevels(.separate, input: histogram, for: photo, blackClip: 0, whiteClip: 0)
        XCTAssertEqual(workspace.selected, combined)
        workspace.applyAutoLevels(.separate, input: histogram, for: combined, blackClip: 0, whiteClip: 0)
        let separate = try XCTUnwrap(workspace.selected)
        XCTAssertEqual(separate.adjustments.levels(for: .red).blackPoint, 20.0 / 255)
        XCTAssertEqual(separate.adjustments.levels(for: .blue).whitePoint, 180.0 / 255)
        XCTAssertEqual(separate.adjustments.levels(for: .green), LevelValues())
        XCTAssertEqual(workspace.library.version, 6)
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected, combined)
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected, separate)
        workspace.edit { $0.adjustments.darkLevelQuarter = 0.42 }
        var blue = try XCTUnwrap(workspace.selected?.adjustments.levels(for: .blue))
        blue.lightQuarter = 0.65
        workspace.setChannelLevels(blue, for: .blue, photoID: photo.id)
        XCTAssertEqual(workspace.library.version, 7)
        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.selected?.adjustments.darkLevelQuarter, 0.42)
        XCTAssertEqual(reopened.selected?.adjustments.levels(for: .blue), blue)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.levels(for: .blue).lightQuarter, 0.75)
    }
}
