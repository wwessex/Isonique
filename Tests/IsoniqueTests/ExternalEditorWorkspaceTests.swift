import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import Isonique
@testable import IsoniqueCore

@MainActor final class ExternalEditorWorkspaceTests: XCTestCase {
    private enum LaunchFailure: LocalizedError {
        case rejected
        var errorDescription: String? { "The test editor refused the document." }
    }

    func testEditorChoicePersistsAndLaunchFailureCleansHandoff() async throws {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueExternalEditorWorkspaceTests-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let suite = "IsoniqueExternalEditorWorkspaceTests-" + UUID().uuidString
        let preferences = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { preferences.removePersistentDomain(forName: suite) }

        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        let source = try makeImage(temporary.appendingPathComponent("Source.png"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        let photo = try XCTUnwrap(library.photos.first)
        let application = temporary.appendingPathComponent("Test Editor.app", isDirectory: true)
        try FileManager.default.createDirectory(at: application, withIntermediateDirectories: false)

        let workspace = Workspace(libraryRoot: repository.root, preferences: preferences)
        workspace.setExternalEditor(application)
        XCTAssertEqual(workspace.externalEditorName, "Test Editor")
        XCTAssertEqual(Workspace(libraryRoot: repository.root, preferences: preferences).externalEditorURL, application)

        let attempted = expectation(description: "launch attempted")
        var stagedDirectory: URL?
        workspace.startExternalEdit(photo, repository: repository, applicationURL: application) { file, _ in
            stagedDirectory = file.deletingLastPathComponent()
            attempted.fulfill()
            throw LaunchFailure.rejected
        }
        await fulfillment(of: [attempted], timeout: 2)
        for _ in 0..<100 where workspace.busy { await Task.yield() }

        XCTAssertFalse(workspace.busy)
        XCTAssertNil(workspace.externalEditHandoff)
        XCTAssertEqual(workspace.status, "External editor handoff failed")
        XCTAssertEqual(workspace.error, LaunchFailure.rejected.localizedDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(stagedDirectory).path))
        XCTAssertEqual(try repository.load().photos.count, 1)
    }

    private func makeImage(_ url: URL) throws -> URL {
        let context = try XCTUnwrap(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8,
                                              bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
