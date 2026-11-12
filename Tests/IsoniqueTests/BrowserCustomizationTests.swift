import CoreGraphics
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor
final class BrowserCustomizationTests: XCTestCase {
    func testListColumnsPersistResetAndMigrateFromOlderPreferenceDomain() throws {
        let folder = temporaryFolder()
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        defer { try? FileManager.default.removeItem(at: folder) }

        let previousDomain = "BrowserColumns.previous.\(UUID())"
        let currentDomain = "BrowserColumns.current.\(UUID())"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: previousDomain)
            UserDefaults.standard.removePersistentDomain(forName: currentDomain)
        }
        var older = TableColumnCustomization<Photo>()
        older[visibility: PhotoListColumn.camera.id] = .hidden
        older[visibility: PhotoListColumn.caption.id] = .visible
        let data = try JSONEncoder().encode(older)
        UserDefaults.standard.setPersistentDomain([
            ListColumnPreferences.key: data,
            "browser.quickPreview": true,
        ], forName: previousDomain)

        AppPreferencesMigration.migrate(from: previousDomain, to: currentDomain)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: currentDomain))
        let migrated = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertFalse(migrated.listColumnIsVisible(.camera))
        XCTAssertTrue(migrated.listColumnIsVisible(.caption))
        XCTAssertTrue(migrated.quickPreview)

        migrated.setListColumn(.lens, visible: true)
        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.listColumnCustomization, migrated.listColumnCustomization)
        XCTAssertTrue(reopened.listColumnIsVisible(.lens))
        XCTAssertFalse(reopened.listColumnIsVisible(.camera))

        reopened.resetListColumns()
        let reset = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertTrue(reset.listColumnIsVisible(.camera))
        XCTAssertFalse(reset.listColumnIsVisible(.caption))
        XCTAssertFalse(reset.listColumnIsVisible(.lens))

        preferences.set(Data("not column JSON".utf8), forKey: ListColumnPreferences.key)
        let recovered = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertTrue(recovered.listColumnIsVisible(.photo))
        XCTAssertTrue(recovered.listColumnIsVisible(.rating))
        XCTAssertFalse(recovered.listColumnIsVisible(.keywords))
    }

    func testQuickPreviewKeepsBrowserSelectionSortFilterAndReviewRouting() throws {
        let folder = temporaryFolder()
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let suite = "QuickPreview.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let alpha = Photo(filename: "alpha.png", originalName: "Alpha.png", projectID: nil,
                          width: 60, height: 40, camera: "Camera A", captureDate: "2026-01-01", sha256: "alpha")
        let beta = Photo(filename: "beta.png", originalName: "Beta.png", projectID: nil,
                         width: 40, height: 60, camera: "Camera B", captureDate: "2026-01-02", sha256: "beta")
        var library = try repository.load()
        library.photos = [beta, alpha]
        try repository.save(library)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.sort = .name
        workspace.selection = alpha.id
        XCTAssertEqual(workspace.photos.map(\.id), [alpha.id, beta.id])
        XCTAssertEqual(KeyboardCommandRouter.command(for: .init("p"), context: .browser,
            preferences: workspace.commandPreferences, textInputActive: false, sheetActive: false), .quickPreview)
        XCTAssertEqual(KeyboardCommandRouter.command(for: .init("p"), context: .viewer,
            preferences: workspace.commandPreferences, textInputActive: false, sheetActive: false), .quickPreview)
        XCTAssertNil(KeyboardCommandRouter.command(for: .init("p"), context: .compare,
            preferences: workspace.commandPreferences, textInputActive: false, sheetActive: false))
        XCTAssertNil(KeyboardCommandRouter.command(for: .init("p"), context: .browser,
            preferences: workspace.commandPreferences, textInputActive: true, sheetActive: false))

        XCTAssertTrue(workspace.performKeyboardCommand(.quickPreview))
        XCTAssertTrue(workspace.quickPreview)
        XCTAssertEqual(workspace.selection, alpha.id)
        XCTAssertEqual(workspace.photos.map(\.id), [alpha.id, beta.id])
        XCTAssertFalse(workspace.canStartComparison)
        XCTAssertTrue(workspace.performKeyboardCommand(.nextPhoto))
        XCTAssertEqual(workspace.selection, beta.id)
        XCTAssertTrue(workspace.performKeyboardCommand(.rating4))
        XCTAssertEqual(workspace.selected?.rating, 4)
        XCTAssertTrue(workspace.quickPreview)
        workspace.ratingFilter = .fourAndAbove
        workspace.search = "Beta"
        XCTAssertEqual(workspace.photos.map(\.id), [beta.id])

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertTrue(reopened.quickPreview)
        XCTAssertEqual(QuickPreviewPolicy.maximumDimension, 1600)
    }

    func testListMetadataPreservesLargeValuesAndFormatsCataloguedEXIF() throws {
        let longCaption = String(repeating: "Editorial caption — ", count: 800)
        let longKeywords = String(repeating: "People|Portrait, Places|London, ", count: 600)
        var photo = Photo(filename: "fixture.jpg", originalName: "Fixture.jpg", projectID: nil,
                          width: 12_000, height: 8_000,
                          camera: String(repeating: "Very Long Camera Name ", count: 40),
                          captureDate: "2026-11-12T20:15:30Z", sha256: "fixture")
        photo.caption = longCaption
        photo.keywords = longKeywords
        photo.cameraEXIF = CameraEXIF(properties: [kCGImagePropertyExifDictionary as String: [
            kCGImagePropertyExifExposureTime as String: 1.0 / 125,
            kCGImagePropertyExifFNumber as String: 2.8,
            kCGImagePropertyExifISOSpeedRatings as String: [640],
            kCGImagePropertyExifFocalLength as String: 35.5,
            kCGImagePropertyExifLensModel as String: String(repeating: "Long Lens ", count: 100),
        ]])

        XCTAssertEqual(PhotoListColumn.caption.value(for: photo), longCaption)
        XCTAssertEqual(PhotoListColumn.keywords.value(for: photo), longKeywords)
        XCTAssertEqual(PhotoListColumn.lens.value(for: photo), photo.cameraEXIF?.lens)
        XCTAssertEqual(PhotoListColumn.shutterSpeed.value(for: photo), "1/125 s")
        XCTAssertEqual(PhotoListColumn.aperture.value(for: photo), "ƒ/2.8")
        XCTAssertEqual(PhotoListColumn.iso.value(for: photo), "640")
        XCTAssertEqual(PhotoListColumn.focalLength.value(for: photo), "35.5 mm")
        XCTAssertEqual(PhotoListColumn.dimensions.value(for: photo), "12000 × 8000")
        XCTAssertEqual(PhotoListColumn.allCases.count, 14)
        XCTAssertTrue(PhotoListColumn.allCases.allSatisfy { $0.minimumWidth > 0 && $0.idealWidth >= $0.minimumWidth })
    }

    func testBrowserPreferencesLeaveCatalogueOriginalsAndEditedExportUnchanged() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.png")
        try writeFixture(source)
        let sourceDigest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments.exposure = 0.35
        library = try repository.save(library)
        let photo = library.photos[0]
        let original = try repository.availableOriginalURL(photo)
        let catalogue = repository.root.appendingPathComponent("catalog.json")
        let catalogueBefore = try Data(contentsOf: catalogue)
        let before = folder.appendingPathComponent("Before.png")
        let after = folder.appendingPathComponent("After.png")
        var options = ExportOptions(); options.format = .png
        try Renderer.export(photo, repository: repository, to: before, options: options)

        let suite = "BrowserIsolation.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.setListColumn(.caption, visible: true)
        workspace.setListColumn(.camera, visible: false)
        workspace.setQuickPreview(true)
        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertTrue(reopened.quickPreview)
        XCTAssertTrue(reopened.listColumnIsVisible(.caption))
        XCTAssertFalse(reopened.listColumnIsVisible(.camera))

        try Renderer.export(photo, repository: repository, to: after, options: options)
        XCTAssertEqual(try LibraryRepository.digest(before), try LibraryRepository.digest(after))
        XCTAssertEqual(try Data(contentsOf: catalogue), catalogueBefore)
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
    }

    func testBritishEnglishContainsListColumnLocalization() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let stringsURL = repositoryRoot.appendingPathComponent("Resources/en-GB.lproj/Localizable.strings")
        let dictionary = try XCTUnwrap(NSDictionary(contentsOf: stringsURL) as? [String: String])
        XCTAssertEqual(dictionary["Customize List Columns"], "Customise List Columns")
        XCTAssertEqual(dictionary["Customize List Columns…"], "Customise List Columns…")
    }

    private func temporaryFolder() -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueBrowser-\(UUID())")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeFixture(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 64, height: 42, bitsPerComponent: 8,
            bytesPerRow: 64 * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(red: 0.18, green: 0.42, blue: 0.72, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 42))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }
}
