import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
import IsoniqueCore
@testable import Isonique

@MainActor
final class PhotographyWorkspaceTests: XCTestCase {
    func testRememberedLayoutsRestoreIndependently() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "PhotographyWorkspaceTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let first = Workspace(libraryRoot: folder.appendingPathComponent("First"), preferences: defaults)
        first.performPhotographyWorkspaceCommand(.togglePanel(.browser))
        first.performPhotographyWorkspaceCommand(.togglePanel(.inspector))
        let editing = first.photographyLayout
        first.performPhotographyWorkspaceCommand(.selectMode(.culling))
        first.performPhotographyWorkspaceCommand(.togglePanel(.filmstrip))
        first.performPhotographyWorkspaceCommand(.togglePanel(.toolbar))
        let culling = first.photographyLayout
        first.performPhotographyWorkspaceCommand(.selectMode(.compare))

        let reopened = Workspace(libraryRoot: folder.appendingPathComponent("Second"), preferences: defaults)
        XCTAssertEqual(reopened.photographyMode, .compare)
        reopened.performPhotographyWorkspaceCommand(.selectMode(.editing))
        XCTAssertEqual(reopened.photographyLayout, editing)
        reopened.performPhotographyWorkspaceCommand(.selectMode(.culling))
        XCTAssertEqual(reopened.photographyLayout, culling)
        XCTAssertEqual(reopened.showInspector, culling.inspector)
    }

    func testPanelCommandsAndFocusSkipHiddenPanels() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "PhotographyWorkspaceFocus-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = Workspace(libraryRoot: folder.appendingPathComponent("Library"), preferences: defaults)

        model.performPhotographyWorkspaceCommand(.togglePanel(.browser))
        model.performPhotographyWorkspaceCommand(.togglePanel(.filmstrip))
        model.performPhotographyWorkspaceCommand(.togglePanel(.inspector))
        XCTAssertEqual(model.visiblePhotographyFocus, [.viewer, .browser, .toolbar])
        model.photographyFocus = .viewer
        model.performPhotographyWorkspaceCommand(.cycleFocus)
        XCTAssertEqual(model.photographyFocus, .browser)
        model.performPhotographyWorkspaceCommand(.cycleFocus)
        XCTAssertEqual(model.photographyFocus, .toolbar)
        model.performPhotographyWorkspaceCommand(.togglePanel(.toolbar))
        XCTAssertEqual(model.photographyFocus, .viewer)
        XCTAssertEqual(model.visiblePhotographyFocus, [.viewer, .browser])
    }

    func testSecondaryDisplayPolicyPreservesScaleAndProfiles() throws {
        let srgb = Data([1, 2, 3])
        let p3 = Data([4, 5, 6, 7])
        let primary = PhotographyDisplayDescriptor(id: 10, name: "Internal",
            frame: CGRect(x: 0, y: 0, width: 1728, height: 1117), backingScale: 2,
            colorSpaceName: "sRGB", iccProfile: srgb)
        let secondary = PhotographyDisplayDescriptor(id: 20, name: "Proof Display",
            frame: CGRect(x: 1728, y: 0, width: 2560, height: 1440), backingScale: 1,
            colorSpaceName: "Display P3", iccProfile: p3)

        XCTAssertNil(PhotographyDisplayPolicy.secondary(from: [primary], primaryID: primary.id))
        let chosen = try XCTUnwrap(PhotographyDisplayPolicy.secondary(from: [primary, secondary],
                                                                       primaryID: primary.id))
        XCTAssertEqual(chosen.id, secondary.id)
        XCTAssertEqual(chosen.maximumPixelDimension, 2560)
        XCTAssertEqual(chosen.colorSpaceName, "Display P3")
        XCTAssertEqual(chosen.iccProfile, p3)
        XCTAssertNotEqual(chosen.backingScale, primary.backingScale)
        XCTAssertNotEqual(chosen.iccProfile, primary.iccProfile)
    }

    func testSecondaryRenderCancellationAndExportRemainNonDestructive() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("Source.png")
        try writeFixture(source, width: 96, height: 64)
        let sourceDigest = try LibraryRepository.digest(source)
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        library.photos[0].adjustments.exposure = 0.45
        library = try repository.save(library)
        let photo = library.photos[0]
        let original = try repository.availableOriginalURL(photo)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let catalogueBefore = try encoder.encode(library)
        let display = PhotographyDisplayDescriptor(id: 20, name: "Proof Display",
            frame: CGRect(x: 0, y: 0, width: 1920, height: 1080), backingScale: 2,
            colorSpaceName: "Display P3", iccProfile: Data([9, 8, 7]))
        let request = SecondaryViewerRequest(photo: photo, revision: 0, display: display,
                                             proofProfile: nil)
        let cache = ViewerRenderCache()

        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await SecondaryViewerLoader.load(photo: photo, request: request,
                repository: repository, cache: cache)
        }
        do {
            _ = try await cancelled.value
            XCTFail("Cancelled full-resolution transition returned an obsolete image")
        } catch is CancellationError {}

        let preview = try await SecondaryViewerLoader.load(photo: photo, request: request,
            repository: repository, cache: cache)
        XCTAssertEqual(preview.rendered.width, 96)
        XCTAssertEqual(preview.rendered.height, 64)
        var changed = photo
        changed.adjustments.exposure = -0.25
        XCTAssertNotEqual(SecondaryViewerRequest(photo: changed, revision: 0, display: display,
                                                  proofProfile: nil), request)

        var options = ExportOptions()
        options.format = .png
        let export = folder.appendingPathComponent("Edited.png")
        try Renderer.export(photo, repository: repository, to: export, options: options)
        XCTAssertEqual(try pixels(preview.rendered), try pixels(decode(export)))
        XCTAssertEqual(try encoder.encode(repository.load()), catalogueBefore)
        XCTAssertEqual(try LibraryRepository.digest(source), sourceDigest)
        XCTAssertEqual(try LibraryRepository.digest(original), sourceDigest)
    }

    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("IsoniquePhotography-\(UUID().uuidString)")
    }

    private func writeFixture(_ url: URL, width: Int, height: Int) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue))
        let colors = [CGColor(red: 0.15, green: 0.3, blue: 0.7, alpha: 1),
                      CGColor(red: 0.8, green: 0.4, blue: 0.1, alpha: 1)] as CFArray
        let gradient = try XCTUnwrap(CGGradient(colorsSpace: space, colors: colors, locations: [0, 1]))
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL,
            UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    private func decode(_ url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func pixels(_ image: CGImage) throws -> Data {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &bytes, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Data(bytes)
    }
}
