import IsoniqueCore
import XCTest
@testable import Isonique

final class IPTCStampTests: XCTestCase {
    @MainActor
    func testMixedStampUsesVisibleSelectionAndPersistsOneUndoStep() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueStamp-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: root, preferences: preferences)
        let project = Collection(name: "Visible project")
        var source = photo("Lifted", project: project.id)
        source.iptc = IPTCMetadata(title: "Lifted title", creators: ["One", "Two"], copyright: "Source rights", credit: "")
        source.adjustments.exposure = 1.5
        source.adjustments.warmth = 0.5
        var first = photo("First", project: project.id)
        first.iptc = IPTCMetadata(title: "First title", copyright: "Keep rights", credit: "Clear this")
        first.adjustments.exposure = -0.5
        var second = photo("Second", project: project.id)
        second.caption = "Keep caption"
        let hidden = photo("Hidden")
        var trashed = photo("Trashed", project: project.id)
        trashed.trashedAt = Date()
        var draft = workspace.library
        draft.projects = [project]
        draft.photos = [source, first, second, hidden, trashed]
        XCTAssertTrue(workspace.commit(draft))

        workspace.scope = "project:\(project.id)"
        workspace.selection = source.id
        workspace.lift()
        XCTAssertEqual(workspace.liftedAdjustments?.source.id, source.id)
        workspace.stampGroups = [.basic]
        workspace.stampMetadata = [.iptcTitle, .iptcCreator, .iptcCredit]
        workspace.batchMode = true
        workspace.batchSelection = [first.id, second.id, hidden.id, trashed.id]
        XCTAssertTrue(workspace.canStamp)
        workspace.stamp()

        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.library.version, 13)
        let stamped = workspace.library.photos
        XCTAssertEqual(stamped[1].iptc, IPTCMetadata(title: "Lifted title", creators: ["One", "Two"],
                                                     copyright: "Keep rights", credit: ""))
        XCTAssertEqual(stamped[2].caption, second.caption)
        XCTAssertEqual(stamped[1].adjustments.exposure, 1.5)
        XCTAssertEqual(stamped[1].adjustments.warmth, first.adjustments.warmth)
        XCTAssertEqual(stamped[3], hidden)
        XCTAssertEqual(stamped[4], trashed)
        workspace.stamp()
        XCTAssertEqual(workspace.history.undo.count, 1)

        let reopened = Workspace(libraryRoot: root, preferences: preferences)
        var later = reopened.library
        later.photos[1].adjustments.warmth = -0.6
        later.photos[1].iptc?.copyright = "Later rights"
        XCTAssertTrue(reopened.commit(later))
        reopened.undoEdit()
        first.adjustments.warmth = -0.6
        first.iptc?.copyright = "Later rights"
        XCTAssertEqual(reopened.library.photos, [source, first, second, hidden, trashed])

        let reopenedAgain = Workspace(libraryRoot: root, preferences: preferences)
        reopenedAgain.redoEdit()
        XCTAssertEqual(reopenedAgain.library.photos, later.photos)
    }

    private func photo(_ name: String, project: UUID? = nil) -> Photo {
        Photo(filename: name + ".jpg", originalName: name + ".jpg", projectID: project,
              width: 32, height: 24, camera: "", captureDate: "", sha256: name)
    }
}
