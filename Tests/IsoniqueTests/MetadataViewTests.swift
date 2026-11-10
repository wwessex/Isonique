import IsoniqueCore
import XCTest
@testable import Isonique

final class MetadataViewTests: XCTestCase {
    @MainActor
    func testCustomFieldsAndSelectionPersistAcrossLibrariesAndDefaultsStayAvailable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueMetadataViews-\(UUID())")
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        defer {
            preferences.removePersistentDomain(forName: root.lastPathComponent)
            try? FileManager.default.removeItem(at: root)
        }
        let firstLibrary = root.appendingPathComponent("First")
        let secondLibrary = root.appendingPathComponent("Second")
        let workspace = Workspace(libraryRoot: firstLibrary, preferences: preferences)
        let firstCatalogue = firstLibrary.appendingPathComponent("catalog.json")
        let catalogueBefore = try Data(contentsOf: firstCatalogue)
        XCTAssertEqual(workspace.metadataViews.selection, .builtIn(.general))

        let view = CustomMetadataView(name: "  Publication  ", fields: [.lens, .caption, .iso, .creator, .lens])
        XCTAssertTrue(workspace.saveMetadataView(view))
        XCTAssertFalse(workspace.saveMetadataView(CustomMetadataView(name: "publication", fields: [.credit])))
        XCTAssertFalse(workspace.saveMetadataView(CustomMetadataView(name: "Empty", fields: [])))
        XCTAssertFalse(workspace.saveMetadataView(CustomMetadataView(name: BuiltInMetadataView.exif.name, fields: [.camera])))
        XCTAssertEqual(try Data(contentsOf: firstCatalogue), catalogueBefore)

        let reopened = Workspace(libraryRoot: secondLibrary, preferences: preferences)
        let selected = try XCTUnwrap(reopened.metadataViews.selectedCustomView)
        XCTAssertEqual(selected.id, view.id)
        XCTAssertEqual(selected.name, "Publication")
        XCTAssertEqual(selected.fields, [.lens, .caption, .iso, .creator])

        let fields: [MetadataViewField] = [.creator, .longitude, .lens, .latitude, .caption]
        XCTAssertTrue(reopened.saveMetadataView(CustomMetadataView(id: selected.id, name: "Press", fields: fields)))
        let reread = Workspace(libraryRoot: firstLibrary, preferences: preferences)
        XCTAssertEqual(reread.metadataViews.customViews.count, 1)
        XCTAssertEqual(reread.metadataViews.selectedCustomView?.name, "Press")
        XCTAssertEqual(reread.metadataViews.selectedCustomView?.fields, fields)
        for builtIn in BuiltInMetadataView.allCases {
            reread.selectMetadataView(.builtIn(builtIn))
            XCTAssertEqual(MetadataViewPreferences.load(from: preferences).selection, .builtIn(builtIn))
            XCTAssertFalse(builtIn.fields.isEmpty)
        }
        XCTAssertEqual(BuiltInMetadataView.exif.fields.filter(\.isEXIF), [.shutterSpeed, .aperture, .iso, .focalLength, .lens])
        XCTAssertEqual(BuiltInMetadataView.gps.fields, [.latitude, .longitude])
        XCTAssertTrue(BuiltInMetadataView.gps.fields.allSatisfy(\.isGPS))
        XCTAssertEqual(BuiltInMetadataView.iptc.fields, [.title, .creator, .copyright, .credit])
        XCTAssertEqual(BuiltInMetadataView.captionAndKeywords.fields, [.caption, .keywords, .keywordPaths])
        reread.selectMetadataView(.custom(view.id))
        reread.deleteMetadataView(view.id)
        let afterDeletion = MetadataViewPreferences.load(from: preferences)
        XCTAssertTrue(afterDeletion.customViews.isEmpty)
        XCTAssertEqual(afterDeletion.selection, .builtIn(.general))
        XCTAssertEqual(try Data(contentsOf: firstCatalogue), catalogueBefore)
    }

    func testUnknownFieldsKeepSupportedOrderAndEmptyViewsFallBackToGeneral() throws {
        let suite = "IsoniqueMetadataViews-\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var initial = MetadataViewPreferences()
        let view = CustomMetadataView(name: "Mixed", fields: [.credit, .caption, .lens])
        XCTAssertTrue(initial.save(view))
        initial.select(.custom(view.id))
        let data = try JSONEncoder().encode(initial)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        preferences.set(Data(json.replacingOccurrences(of: "\"caption\"", with: "\"futureField\"").utf8),
                        forKey: MetadataViewPreferences.key)
        XCTAssertEqual(MetadataViewPreferences.load(from: preferences).selectedCustomView?.fields, [.credit, .lens])
        let unknownOnly = json.replacingOccurrences(of: #""fields":\[[^\]]+\]"#,
                                                    with: #""fields":["futureField"]"#, options: .regularExpression)
        preferences.set(Data(unknownOnly.utf8), forKey: MetadataViewPreferences.key)
        XCTAssertEqual(MetadataViewPreferences.load(from: preferences).selection, .builtIn(.general))
    }
}
