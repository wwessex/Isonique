import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import Isonique
@testable import IsoniqueCore

@MainActor final class PrintLayoutWorkspaceTests: XCTestCase {
    func testPrintScopeUsesBrowserOrExplicitBatchSelection() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniquePrintScopeTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        let project = Collection(name: "Print project")
        library.projects.append(project)
        for index in 0..<3 {
            let source = try image(temporary.appendingPathComponent("Proof-\(index).png"),
                                   red: CGFloat(index + 1) / 4)
            XCTAssertTrue(try repository.importPhoto(source, projectID: index < 2 ? project.id : nil, into: &library))
        }
        let suite = "IsoniquePrintScopeTests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.scope = "project:\(project.id)"
        XCTAssertEqual(Set(workspace.printPhotos.map(\.id)), Set(library.photos.prefix(2).map(\.id)))

        workspace.batchMode = true
        workspace.batchSelection = [library.photos[2].id]
        XCTAssertEqual(workspace.printPhotos.map(\.id), [library.photos[2].id])
    }

    func testNativePrintOperationAndPresetPersistence() throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniquePrintWorkspaceTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        let source = try image(temporary.appendingPathComponent("Proof.png"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))

        let options = PrintLayoutOptions(style: .proof, pageSize: .letter, orientation: .landscape,
                                         marginPoints: 48, caption: .filename, colourMode: .displayP3)
        let data = try PrintLayout.pdfData(photos: library.photos, repository: repository, options: options)
        let operation = try NativePrintBridge.operation(pdfData: data, options: options)
        XCTAssertEqual(operation.printInfo.paperSize.width, options.pageDimensions.width, accuracy: 0.01)
        XCTAssertEqual(operation.printInfo.paperSize.height, options.pageDimensions.height, accuracy: 0.01)
        XCTAssertEqual(operation.printInfo.orientation, .landscape)
        XCTAssertTrue(operation.showsPrintPanel)
        XCTAssertTrue(operation.showsProgressPanel)

        let suite = "IsoniquePrintPresetTests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }
        let presets = [PrintPreset(name: "Landscape Proof", options: options)]
        preferences.set(PrintPresetStorage.encode(presets), forKey: PrintPresetStorage.key)
        let reopened = try XCTUnwrap(UserDefaults(suiteName: suite))
        XCTAssertEqual(PrintPresetStorage.decode(try XCTUnwrap(reopened.data(forKey: PrintPresetStorage.key))), presets)
    }

    private func image(_ url: URL, red: CGFloat = 0.2) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 16, height: 12, bitsPerComponent: 8,
                                              bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 12))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
