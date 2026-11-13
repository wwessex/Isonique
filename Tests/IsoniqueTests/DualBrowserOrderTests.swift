import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor
final class DualBrowserOrderTests: XCTestCase {
    func testSecondBrowserKeepsIndependentScopeSelectionReviewFocusAndOlderPreferences() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let project = Collection(name: "Independent Project")
        let alpha = photo("Alpha.jpg", projectID: nil, date: 1)
        let beta = photo("Beta.jpg", projectID: project.id, date: 2)
        let gamma = photo("Gamma.jpg", projectID: project.id, date: 3)
        var library = try repository.load()
        library.projects = [project]
        library.photos = [alpha, beta, gamma]
        _ = try repository.save(library)

        let suite = "DualBrowser.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let older = "{\"visible\":true,\"scope\":\"project:\(project.id)\",\"search\":\"Beta\"}"
        preferences.set(Data(older.utf8), forKey: SecondaryBrowserPreferences.key)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.selection = alpha.id
        XCTAssertTrue(workspace.secondaryBrowser.visible)
        XCTAssertEqual(workspace.normalizedSecondaryScope, "project:\(project.id)")
        XCTAssertEqual(workspace.secondaryPhotos.map(\.id), [beta.id])
        XCTAssertEqual(workspace.secondaryBrowser.sort, .imported)
        XCTAssertEqual(workspace.secondaryBrowser.rating, .all)

        workspace.secondaryBrowser.search = ""
        workspace.secondaryBrowserSelection = beta.id
        workspace.activeBrowserPane = .secondary
        XCTAssertTrue(workspace.performKeyboardCommand(.rating4))
        XCTAssertEqual(workspace.library.photos.first { $0.id == beta.id }?.rating, 4)
        XCTAssertEqual(workspace.selection, alpha.id)
        XCTAssertTrue(workspace.performKeyboardCommand(.nextPhoto))
        XCTAssertEqual(workspace.secondaryBrowserSelection, gamma.id)
        XCTAssertEqual(workspace.selection, alpha.id)

        workspace.activeBrowserPane = .primary
        XCTAssertTrue(workspace.performKeyboardCommand(.rating2))
        XCTAssertEqual(workspace.library.photos.first { $0.id == alpha.id }?.rating, 2)
        XCTAssertEqual(workspace.secondaryBrowserSelection, gamma.id)
        workspace.secondaryBrowser.descending = true

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertTrue(reopened.secondaryBrowser.visible)
        XCTAssertEqual(reopened.normalizedSecondaryScope, "project:\(project.id)")
        XCTAssertTrue(reopened.secondaryBrowser.descending)
        XCTAssertEqual(reopened.secondaryPhotos.map(\.id), [gamma.id, beta.id])
    }

    func testManualOrderMovesCollapsedStackAndVersionWithUndoRedoAndRestart() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let stackID = UUID()
        var first = photo("Stack One.jpg", projectID: nil, date: 1); first.stackID = stackID
        var second = photo("Stack Two.jpg", projectID: nil, date: 2); second.stackID = stackID
        let third = photo("Third.jpg", projectID: nil, date: 3)
        var version = photo("Version.jpg", projectID: nil, date: 4)
        version.sharedOriginalID = first.id
        version.filename = first.filename
        version.sha256 = first.sha256
        var library = try repository.load()
        library.photos = [first, second, third, version]
        library.setStackCollapsed(true, stackID: stackID)
        _ = library.applyStackPick(StackPickChange(stackID: stackID, photoID: first.id, selectionID: first.id))
        _ = try repository.save(library)

        let suite = "ManualOrder.\(UUID())"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(workspace.photos.map(\.id), [first.id, third.id, version.id])
        XCTAssertEqual(workspace.manualMoveIDs(for: first, scope: "all"), [first.id, second.id])

        workspace.moveManualPhotos([first.id, second.id], before: nil, scope: "all")
        XCTAssertEqual(workspace.sort, .manual)
        XCTAssertEqual(workspace.library.version, 36)
        XCTAssertEqual(workspace.photos.map(\.id), [third.id, version.id, first.id])
        workspace.undoEdit()
        XCTAssertEqual(workspace.photos.map(\.id), [first.id, third.id, version.id])
        workspace.redoEdit()
        XCTAssertEqual(workspace.photos.map(\.id), [third.id, version.id, first.id])

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.sort, .manual)
        XCTAssertEqual(reopened.photos.map(\.id), [third.id, version.id, first.id])
        XCTAssertEqual(reopened.library.browserOrders?.ids(in: "all"), [third.id, version.id, first.id, second.id])
    }

    func testManualOrderEligibilityProtectsDerivedContainersAndOlderCatalogues() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let project = Collection(name: "Project")
        let album = Collection(name: "Album")
        var smart = Collection(name: "Smart")
        smart.rule = SmartAlbumRule(minimumRating: 3)
        var member = photo("Member.jpg", projectID: project.id, date: 1)
        member.albumIDs = [album.id]
        var library = try repository.load()
        library.projects = [project]
        library.albums = [album, smart]
        library.photos = [member]
        _ = try repository.save(library)

        let workspace = Workspace(libraryRoot: repository.root)
        XCTAssertEqual(workspace.manualOrderScope(for: "all"), "all")
        XCTAssertEqual(workspace.manualOrderScope(for: "project:\(project.id)"), "project:\(project.id)")
        XCTAssertEqual(workspace.manualOrderScope(for: "album:\(album.id)"), "album:\(album.id)")
        XCTAssertNil(workspace.manualOrderScope(for: "album:\(smart.id)"))
        XCTAssertNil(workspace.manualOrderScope(for: "flagged"))
        XCTAssertNil(workspace.manualOrderScope(for: "trash"))
        XCTAssertNil(workspace.manualOrderScope(for: "stack:\(UUID())"))

        let older = try JSONEncoder().encode(Library())
        let decoded = try JSONDecoder().decode(Library.self, from: older)
        XCTAssertEqual(decoded.version, 1)
        XCTAssertNil(decoded.browserOrders)

        var mislabeled = Library()
        mislabeled.version = 35
        var order = BrowserOrderState()
        order.set([member.id], in: "all")
        mislabeled.browserOrders = order
        XCTAssertThrowsError(try mislabeled.validateSchema())
    }

    func testManualOrderPreservesRecipesOriginalsAndEditedExport() throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.png")
        try writeFixture(source, red: 0.2, green: 0.45, blue: 0.75)
        let sourceDigest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments.exposure = 0.4
        var version = library.photos[0]
        version.id = UUID(); version.sharedOriginalID = library.photos[0].originalID
        version.versionName = "Alternate"; version.adjustments.contrast = 1.2
        library.photos.append(version)
        library.version = max(library.version, 3)
        library = try repository.save(library)
        let original = try repository.availableOriginalURL(library.photos[0])
        let recipes = Dictionary(uniqueKeysWithValues: library.photos.map { ($0.id, $0.adjustments) })
        var options = ExportOptions(); options.format = .png
        let before = folder.appendingPathComponent("Before.png")
        let after = folder.appendingPathComponent("After.png")
        try Renderer.export(library.photos[0], repository: repository, to: before, options: options)

        let workspace = Workspace(libraryRoot: repository.root)
        workspace.moveManualPhotos([version.id], before: library.photos[0].id, scope: "all")
        try Renderer.export(try XCTUnwrap(workspace.library.photos.first { $0.id == library.photos[0].id }),
                            repository: repository, to: after, options: options)
        XCTAssertEqual(try LibraryRepository.digest(before), try LibraryRepository.digest(after))
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: workspace.library.photos.map { ($0.id, $0.adjustments) }), recipes)
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
    }

    func testProjectExportAndCollisionImportPreserveManualMembershipOrders() async throws {
        let folder = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("SourceLibrary"))
        let project = Collection(name: "Ordered Project")
        let album = Collection(name: "Ordered Album")
        var library = try repository.load()
        library.projects = [project]
        library.albums = [album]
        for (index, color) in [(0, 0.15), (1, 0.45), (2, 0.75)] {
            let source = folder.appendingPathComponent("Source-\(index).png")
            try writeFixture(source, red: color, green: 0.3, blue: 0.8 - color / 2)
            XCTAssertTrue(try repository.importPhoto(source, projectID: project.id, into: &library))
            library.photos[library.photos.count - 1].albumIDs.insert(album.id)
        }
        let ordered = library.photos.map(\.id).reversed()
        var orders = BrowserOrderState()
        orders.set(Array(ordered), in: "project:\(project.id)")
        orders.set(Array(ordered), in: "album:\(album.id)")
        library.browserOrders = orders
        library.upgradeForBrowserOrders()
        _ = try repository.save(library)

        let exportedRoot = folder.appendingPathComponent("Exported")
        XCTAssertEqual(try LibraryBackup.exportProject(project.id, from: repository, to: exportedRoot), 3)
        let exported = try LibraryRepository(root: exportedRoot).load()
        XCTAssertEqual(exported.browserOrders?.ids(in: "all"), Array(ordered))
        XCTAssertEqual(exported.browserOrders?.ids(in: "project:\(project.id)"), Array(ordered))

        let destination = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Destination"))
        let first = try await destination.importProjectLibrary(from: exportedRoot)
        let firstProjectOrder = try XCTUnwrap(first.library.browserOrders?.ids(in: "project:\(first.project.id)"))
        XCTAssertEqual(firstProjectOrder.count, 3)
        let second = try await destination.importProjectLibrary(from: exportedRoot, basedOn: first.library)
        let secondProjectOrder = try XCTUnwrap(second.library.browserOrders?.ids(in: "project:\(second.project.id)"))
        XCTAssertEqual(secondProjectOrder.count, 3)
        XCTAssertTrue(Set(firstProjectOrder).isDisjoint(with: Set(secondProjectOrder)))
        XCTAssertEqual(second.library.projects.count, 2)
        XCTAssertEqual(second.library.photos.count, 6)
    }

    private func photo(_ name: String, projectID: UUID?, date: TimeInterval) -> Photo {
        var value = Photo(filename: name, originalName: name, projectID: projectID,
                          width: 80, height: 60, camera: "Test Camera", captureDate: "", sha256: name)
        value.importedAt = Date(timeIntervalSince1970: date)
        return value
    }

    private func temporaryFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueDualBrowser-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private func writeFixture(_ url: URL, red: CGFloat, green: CGFloat, blue: CGFloat) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8,
            bytesPerRow: 48 * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }
}
