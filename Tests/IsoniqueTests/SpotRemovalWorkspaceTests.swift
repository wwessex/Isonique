import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore
@testable import Isonique

final class SpotRemovalWorkspaceTests: XCTestCase {
    @MainActor
    func testMultipleSpotEditsUndoRedoAndPersistWithoutChangingOriginal() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueSpotWorkspace-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let suite = "IsoniqueSpotWorkspace-\(UUID().uuidString)"
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: folder)
            preferences.removePersistentDomain(forName: suite)
        }
        preferences.set(true, forKey: "history.persist")
        let source = folder.appendingPathComponent("Source.png")
        try makeImage(source)
        let digest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        try repository.save(library)
        let photoID = try XCTUnwrap(library.photos.first?.id)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.selection = photoID
        workspace.chooseSpotRemoval(.repair)
        XCTAssertEqual(workspace.tool, .spot)
        workspace.placeSpotPoint(BrushPoint(x: 0.2, y: 0.25), radius: 0.06, in: photoID)
        XCTAssertEqual(workspace.history.undo.count, 0, "A source alone is only a draft")
        workspace.placeSpotPoint(BrushPoint(x: 0.42, y: 0.5), radius: 0.06, in: photoID)
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.first?.mode, .repair)

        workspace.beginNewSpot()
        workspace.setSelectedSpotMode(.clone)
        workspace.placeSpotPoint(BrushPoint(x: 0.65, y: 0.3), radius: 0.09, in: photoID)
        workspace.placeSpotPoint(BrushPoint(x: 0.8, y: 0.72), radius: 0.09, in: photoID)
        XCTAssertEqual(workspace.history.undo.count, 2)
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.count, 2)
        let secondID = try XCTUnwrap(workspace.selectedSpotID)

        workspace.spotPlacement = .destination
        workspace.placeSpotPoint(BrushPoint(x: 0.82, y: 0.68), radius: 0.09, in: photoID)
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.last?.destination,
                       BrushPoint(x: 0.82, y: 0.68))
        workspace.spotPlacement = .source
        workspace.placeSpotPoint(BrushPoint(x: 0.6, y: 0.35), radius: 0.09, in: photoID)
        workspace.setSelectedSpotRadius(0.12)
        XCTAssertEqual(workspace.history.undo.count, 5)
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.last?.radius, 0.12)
        workspace.undoEdit()
        XCTAssertEqual(workspace.tool, .spot)
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.last?.radius, 0.09)
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.last?.radius, 0.12)
        workspace.setSelectedSpotMode(.repair)
        XCTAssertEqual(workspace.history.undo.count, 6)
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.last?.mode, .repair)

        workspace.deleteSelectedSpot()
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.count, 1)
        workspace.undoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.count, 2)
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.last?.id, secondID)
        workspace.redoEdit()
        XCTAssertEqual(workspace.selected?.adjustments.spotRemovals.count, 1)
        workspace.undoEdit()

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        reopened.selection = photoID
        XCTAssertEqual(reopened.library.version, 19)
        XCTAssertEqual(reopened.selected?.adjustments.spotRemovals.count, 2)
        XCTAssertEqual(reopened.selected?.adjustments.spotRemovals.last?.mode, .repair)
        XCTAssertEqual(reopened.selected?.adjustments.spotRemovals.last?.radius, 0.12)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.spotRemovals.last?.mode, .clone)
        reopened.redoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.spotRemovals.last?.mode, .repair)
        reopened.clearSpots()
        XCTAssertTrue(reopened.selected?.adjustments.spotRemovals.isEmpty == true)
        reopened.undoEdit()
        XCTAssertEqual(reopened.selected?.adjustments.spotRemovals.count, 2)
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
        let persistedPhoto = try XCTUnwrap(reopened.selected)
        XCTAssertEqual(try LibraryRepository.digest(repository.availableOriginalURL(persistedPhoto)), digest)
    }

    private func makeImage(_ url: URL) throws {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: 96, height: 64, bitsPerComponent: 8,
                                              bytesPerRow: 96 * 4, space: space,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                  CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(red: 0.3, green: 0.4, blue: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 96, height: 64))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
    }
}
