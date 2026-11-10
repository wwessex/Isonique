import IsoniqueCore
import XCTest
@testable import Isonique

final class MetadataPresetTests: XCTestCase {
    @MainActor
    func testPresetPersistsAcrossLibrariesAndAppliesThroughBatchReview() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueMetadataPreset-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = Workspace(libraryRoot: root.appendingPathComponent("One"), preferences: preferences)
        let values = MetadataPresetValues(caption: "", keywordMode: .append, keywords: "Studio, Archive",
                                          iptc: IPTCMetadata(creators: ["Jo Weiß", "Alex Ng"], credit: "Desk"))
        XCTAssertFalse(workspace.saveMetadataPreset(named: " ", values: values))
        XCTAssertFalse(workspace.saveMetadataPreset(named: "Empty", values: MetadataPresetValues()))
        XCTAssertTrue(workspace.saveMetadataPreset(named: " News ", values: values))
        XCTAssertFalse(workspace.saveMetadataPreset(named: "news", values: values))
        let preset = try XCTUnwrap(workspace.metadataPresets.first)
        XCTAssertEqual(preset.name, "News")

        let reopened = Workspace(libraryRoot: root.appendingPathComponent("Two"), preferences: preferences)
        XCTAssertEqual(reopened.metadataPresets, [preset])
        var first = Photo(filename: "a.jpg", originalName: "A.jpg", projectID: nil, width: 20, height: 20,
                          camera: "", captureDate: "", sha256: "A")
        first.caption = "Clear this"
        first.keywords = "studio"
        first.iptc = IPTCMetadata(copyright: "Keep")
        let second = Photo(filename: "b.jpg", originalName: "B.jpg", projectID: nil, width: 20, height: 20,
                           camera: "", captureDate: "", sha256: "B")
        var draft = reopened.library
        draft.photos = [first, second]
        XCTAssertTrue(reopened.commit(draft))
        reopened.selection = first.id
        reopened.openBatchMetadata()
        let review = try XCTUnwrap(reopened.batchMetadataReview)
        let preview = review.preview(preset.values)
        XCTAssertEqual(preview.rows.map(\.id), [first.id])
        XCTAssertEqual(preview.rows.first?.after.keywords, "studio, Archive")
        XCTAssertTrue(reopened.applyBatchMetadata(preview, for: review))
        XCTAssertEqual(reopened.library.photos.first?.caption, "")
        XCTAssertEqual(reopened.library.photos.first?.iptc,
                       IPTCMetadata(creators: ["Jo Weiß", "Alex Ng"], copyright: "Keep", credit: "Desk"))
        XCTAssertEqual(reopened.library.photos.last, second)
        reopened.undoEdit()
        XCTAssertEqual(reopened.library.photos, [first, second])
        reopened.redoEdit()
        XCTAssertEqual(reopened.library.photos.first?.iptc?.credit, "Desk")
        reopened.deleteMetadataPreset(preset.id)
        XCTAssertTrue(MetadataPresetPreferences.load(from: preferences).isEmpty)
        XCTAssertEqual(reopened.library.photos.first?.iptc?.credit, "Desk")
    }
}
