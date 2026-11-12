import AppKit
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import Isonique
@testable import IsoniqueCore

@MainActor final class LightTableWorkspaceTests: XCTestCase {
    func testFilteredSelectionArrangementUndoRedoReusableLayoutsAndPersistence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueLightTableWorkspaceTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
        var library = try repository.load()
        for (index, dimensions) in [(100, 40), (45, 110), (80, 80), (120, 60)].enumerated() {
            let source = try image(root.appendingPathComponent("Photo-\(index).png"),
                                   width: dimensions.0, height: dimensions.1,
                                   red: CGFloat(index + 1) / 5)
            XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        }
        for index in 0..<3 { library.photos[index].caption = "Board choice" }
        library.photos[0].adjustments.exposure = 0.2
        library = try repository.save(library)
        let recipes = library.photos.map(\.adjustments)
        let originals = try library.photos.map { try Data(contentsOf: repository.availableOriginalURL($0)) }

        let suite = "IsoniqueLightTableWorkspaceTests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.search = "Board choice"
        workspace.batchMode = true
        workspace.batchSelection = Set(workspace.library.photos.map(\.id))
        workspace.createLightTable()

        var layout = try XCTUnwrap(workspace.activeLightTable)
        XCTAssertEqual(layout.items.count, 3, "Filtered-out selections must not enter the Light Table")
        XCTAssertEqual(Set(layout.items.map(\.photoID)), Set(workspace.library.photos.prefix(3).map(\.id)))
        XCTAssertEqual(workspace.library.version, 35)

        let first = layout.items[0].id, second = layout.items[1].id
        let historyBeforeMove = workspace.history.undo.count
        workspace.moveLightTableItem(first, in: layout.id, to: CGPoint(x: 420, y: 310))
        XCTAssertEqual(workspace.history.undo.count, historyBeforeMove + 1)
        XCTAssertEqual(workspace.activeLightTable?.items.first { $0.id == first }?.centerX, 420)
        workspace.undoEdit()
        XCTAssertNotEqual(workspace.activeLightTable?.items.first { $0.id == first }?.centerX, 420)
        workspace.redoEdit()
        XCTAssertEqual(workspace.activeLightTable?.items.first { $0.id == first }?.centerX, 420)

        workspace.resizeLightTableItem(first, in: layout.id, to: CGSize(width: 500, height: 210))
        workspace.rotateLightTableItems([first, second], in: layout.id, by: 15)
        workspace.alignLightTableItems([first, second], in: layout.id, to: .top)
        workspace.bringLightTableItemsToFront([first], in: layout.id)
        layout = try XCTUnwrap(workspace.activeLightTable)
        XCTAssertEqual(layout.items.first { $0.id == first }?.width, 500)
        XCTAssertEqual(layout.items.first { $0.id == first }?.rotation, 15)
        let topEdges = [first, second].compactMap { id in
            layout.items.first { $0.id == id }.map { $0.centerY - $0.height / 2 }
        }
        XCTAssertEqual(topEdges[0], topEdges[1], accuracy: 0.000_001)
        XCTAssertEqual(layout.items.max(by: { $0.zIndex < $1.zIndex })?.id, first)

        workspace.renameLightTable(layout.id, to: "Client Selects")
        workspace.duplicateLightTable(layout.id)
        let duplicate = try XCTUnwrap(workspace.activeLightTable)
        XCTAssertNotEqual(duplicate.id, layout.id)
        XCTAssertEqual(duplicate.items.map(\.photoID), layout.items.map(\.photoID))
        workspace.renameLightTable(duplicate.id, to: "Reusable Client Layout")
        workspace.deleteLightTable(duplicate.id)
        XCTAssertNil(workspace.library.lightTables?.first { $0.id == duplicate.id })
        workspace.undoEdit()
        XCTAssertEqual(workspace.library.lightTables?.first { $0.id == duplicate.id }?.name,
                       "Reusable Client Layout")

        let reopened = Workspace(libraryRoot: repository.root, preferences: preferences)
        XCTAssertEqual(reopened.lightTables.count, 2)
        XCTAssertEqual(reopened.library.photos.map(\.adjustments), recipes)
        for (index, photo) in reopened.library.photos.enumerated() {
            XCTAssertEqual(try Data(contentsOf: repository.availableOriginalURL(photo)), originals[index])
        }
    }

    func testNativePrintBridgeAcceptsLightTablePDF() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueLightTablePrintTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
        var library = try repository.load()
        let source = try image(root.appendingPathComponent("Print.png"), width: 80, height: 50, red: 0.4)
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        let layout = LightTableLayout(name: "Print Layout", photos: library.photos)
        let data = try LightTableOutput.pdfData(layout: layout, photos: library.photos,
                                                repository: repository)
        let operation = try NativeLightTablePrintBridge.operation(pdfData: data)
        XCTAssertTrue(operation.showsPrintPanel)
        XCTAssertTrue(operation.showsProgressPanel)
        XCTAssertEqual(LightTableCanvasScale.value(viewport: CGSize(width: 840, height: 540),
                                                   canvas: CGSize(width: 1600, height: 1000),
                                                   actualSize: false), 0.5, accuracy: 0.000_001)
        XCTAssertEqual(LightTableCanvasScale.value(viewport: CGSize(width: 840, height: 540),
                                                   canvas: CGSize(width: 1600, height: 1000),
                                                   actualSize: true), 1)
    }

    private func image(_ url: URL, width: Int, height: Int, red: CGFloat) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.55, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
