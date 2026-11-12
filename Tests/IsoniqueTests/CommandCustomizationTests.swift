import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import IsoniqueCore
@testable import Isonique

@MainActor
final class CommandCustomizationTests: XCTestCase {
    func testDefaultsMigrationNamedSetsAndRestartPersistence() throws {
        XCTAssertEqual(KeyboardCommandDefinition.definitions.count, 32)
        let defaults = KeyboardCommandPreferences()
        XCTAssertEqual(defaults.shortcut(for: .toggleBrowser),
                       .init("b", modifiers: [.command, .option]))
        XCTAssertEqual(defaults.shortcut(for: .rating5), .init("5"))
        XCTAssertEqual(defaults.shortcut(for: .nextPhoto), .init("right"))

        struct LegacyPreferences: Encodable {
            let activeSetID: String
            let sets: [LegacySet]
        }
        struct LegacySet: Encodable {
            let id: String
            let name: String
            let bindings: [String: KeyboardCommandShortcut]
        }
        let legacy = LegacyPreferences(activeSetID: "legacy", sets: [
            .init(id: KeyboardCommandPreferences.defaultSetID, name: "Isonique Default", bindings: [:]),
            .init(id: "legacy", name: "Studio", bindings: [
                IsoniqueKeyboardCommand.toggleBrowser.rawValue: .init("x", modifiers: [.control])
            ])
        ])
        let migrated = try JSONDecoder().decode(KeyboardCommandPreferences.self,
                                                 from: JSONEncoder().encode(legacy))
        XCTAssertEqual(migrated.activeSet.name, "Studio")
        XCTAssertEqual(migrated.shortcut(for: .toggleBrowser), .init("x", modifiers: [.control]))
        XCTAssertEqual(migrated.shortcut(for: .toggleFilmstrip),
                       KeyboardCommandDefinition.byCommand[.toggleFilmstrip]?.defaultShortcut)

        let suite = "CommandCustomization-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        var saved = migrated
        saved.createSet(named: "Studio", copying: migrated.activeSet)
        try saved.renameActive("Editing")
        try saved.setShortcut(.init("j", modifiers: [.control]), for: .nextPhoto)
        saved.save(to: preferences)
        let reopened = KeyboardCommandPreferences.load(from: preferences)
        XCTAssertEqual(reopened.activeSet.name, "Editing")
        XCTAssertEqual(reopened.shortcut(for: .nextPhoto), .init("j", modifiers: [.control]))
        var reset = reopened
        try reset.resetActive()
        XCTAssertEqual(reset.shortcut(for: .nextPhoto), .init("right"))
        try reset.deleteActive()
        XCTAssertEqual(reset.activeSetID, KeyboardCommandPreferences.defaultSetID)
    }

    func testCollisionProtectionAndContextRouting() throws {
        var preferences = KeyboardCommandPreferences()
        preferences.createSet(named: "Custom")
        XCTAssertThrowsError(try preferences.setShortcut(.init("g", modifiers: [.control]),
                                                          for: .listBrowser)) { error in
            XCTAssertEqual(error as? KeyboardCommandPreferencesError, .conflict("Grid Browser"))
        }
        XCTAssertThrowsError(try preferences.setShortcut(.init("1", modifiers: [.option]),
                                                          for: .toggleBrowser)) { error in
            XCTAssertEqual(error as? KeyboardCommandPreferencesError, .conflict("Add Keyword 1"))
        }
        XCTAssertThrowsError(try preferences.setShortcut(.init("c", modifiers: [.command]),
                                                          for: .toggleBrowser)) { error in
            XCTAssertEqual(error as? KeyboardCommandPreferencesError, .conflict("Copy"))
        }

        let shared = KeyboardCommandShortcut("b", modifiers: [.command, .shift])
        try preferences.setShortcut(shared, for: .endCompare)
        XCTAssertEqual(KeyboardCommandRouter.command(for: shared, context: .browser,
            preferences: preferences, textInputActive: false, sheetActive: false), .batchChange)
        XCTAssertEqual(KeyboardCommandRouter.command(for: shared, context: .compare,
            preferences: preferences, textInputActive: false, sheetActive: false), .endCompare)
        XCTAssertNil(KeyboardCommandRouter.command(for: shared, context: .browser,
            preferences: preferences, textInputActive: true, sheetActive: false))
        XCTAssertNil(KeyboardCommandRouter.command(for: shared, context: .compare,
            preferences: preferences, textInputActive: false, sheetActive: true))
    }

    func testImportExportRoundTripDuplicateNamesAndInvalidConflicts() throws {
        var source = KeyboardCommandPreferences()
        source.createSet(named: "Culling")
        try source.setShortcut(.init("n", modifiers: [.control]), for: .nextPhoto)
        try source.setShortcut(nil, for: .loupe)
        let data = try source.exportData()

        var destination = KeyboardCommandPreferences()
        destination.createSet(named: "Culling")
        try destination.importSet(from: data)
        XCTAssertEqual(destination.activeSet.name, "Culling 2")
        XCTAssertEqual(destination.shortcut(for: .nextPhoto), .init("n", modifiers: [.control]))
        XCTAssertNil(destination.shortcut(for: .loupe))

        let collision = KeyboardCommandShortcut("x", modifiers: [.control])
        let invalid = KeyboardCommandSet(name: "Invalid", bindings: [
            IsoniqueKeyboardCommand.toggleBrowser.rawValue: collision,
            IsoniqueKeyboardCommand.toggleInspector.rawValue: collision,
        ])
        XCTAssertThrowsError(try destination.importSet(from: JSONEncoder().encode(invalid))) { error in
            XCTAssertEqual(error as? KeyboardCommandPreferencesError, .invalidImport)
        }
    }

    func testToolbarPersistenceOrderResetAndUnknownCompatibility() throws {
        let suite = "ToolbarCustomization-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var configuration = IsoniqueToolbarConfiguration()
        configuration.setVisible(.features, visible: false)
        configuration.move(.exportPhotos, by: -3)
        configuration.itemIDs.append("future-item")
        configuration.save(to: defaults)
        let reopened = IsoniqueToolbarConfiguration.load(from: defaults)
        XCTAssertFalse(reopened.items.contains(.features))
        XCTAssertEqual(reopened.items[2], .exportPhotos)
        XCTAssertFalse(reopened.items.map(\.rawValue).contains("future-item"))
        var reset = reopened
        reset.reset()
        XCTAssertEqual(reset.items, IsoniqueToolbarItem.defaultItems)
    }

    func testWorkspacePreferencesDoNotChangeCatalogueOriginalOrExport() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.png")
        try writeFixture(source)
        let sourceDigest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments.exposure = 0.4
        library = try repository.save(library)
        let photo = library.photos[0]
        let original = try repository.availableOriginalURL(photo)
        let catalogueBefore = try Data(contentsOf: repository.root.appendingPathComponent("catalog.json"))
        var options = ExportOptions()
        options.format = .png
        let before = folder.appendingPathComponent("Before.png")
        let after = folder.appendingPathComponent("After.png")
        try Renderer.export(photo, repository: repository, to: before, options: options)

        let suite = "CommandWorkspace-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let workspace = Workspace(libraryRoot: repository.root, preferences: defaults)
        workspace.setToolbarItem(.features, visible: false)
        workspace.moveToolbarItem(.exportPhotos, by: -2)
        workspace.createCommandSet(named: "Proofing")
        try workspace.setCommandShortcut(.init("x", modifiers: [.control]), for: .clippingWarnings)
        let reopened = Workspace(libraryRoot: repository.root, preferences: defaults)
        XCTAssertEqual(reopened.activeKeyboardCommandSet.name, "Proofing")
        XCTAssertFalse(reopened.toolbarConfiguration.items.contains(.features))

        try Renderer.export(photo, repository: repository, to: after, options: options)
        XCTAssertEqual(try LibraryRepository.digest(before), try LibraryRepository.digest(after))
        XCTAssertEqual(try Data(contentsOf: repository.root.appendingPathComponent("catalog.json")),
                       catalogueBefore)
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
    }

    func testBritishEnglishContainsNewToolbarLocalization() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let stringsURL = repositoryRoot.appendingPathComponent("Resources/en-GB.lproj/Localizable.strings")
        let dictionary = try XCTUnwrap(NSDictionary(contentsOf: stringsURL) as? [String: String])
        XCTAssertEqual(dictionary["Customize Toolbar"], "Customise Toolbar")
        XCTAssertEqual(dictionary["Customize Toolbar…"], "Customise Toolbar…")
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueCommands-\(UUID().uuidString)")
    }

    private func writeFixture(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8,
            bytesPerRow: 48 * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }
}
