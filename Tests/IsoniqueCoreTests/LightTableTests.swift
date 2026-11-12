import CoreGraphics
import ImageIO
import XCTest
import UniformTypeIdentifiers
@testable import IsoniqueCore

final class LightTableTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueLightTableTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temporary) }

    func testMixedAspectArrangementGeometryAlignmentOrderAndRoundTrip() throws {
        let photos = [photo("Wide", width: 1600, height: 600),
                      photo("Tall", width: 500, height: 1400),
                      photo("Square", width: 900, height: 900)]
        var layout = LightTableLayout(name: "Editorial Board", photos: photos)
        XCTAssertEqual(layout.items.count, 3)
        XCTAssertGreaterThan(layout.items[0].width / layout.items[0].height, 2)
        XCTAssertLessThan(layout.items[1].width / layout.items[1].height, 0.5)

        let first = layout.items[0].id, second = layout.items[1].id
        layout.move(first, to: CGPoint(x: -50, y: 2_000))
        XCTAssertEqual(layout.items.first { $0.id == first }?.centerX, 0)
        XCTAssertEqual(layout.items.first { $0.id == first }?.centerY, layout.canvasHeight)
        layout.resize(second, to: CGSize(width: 12, height: 2_000))
        XCTAssertEqual(layout.items.first { $0.id == second }?.width, 48)
        XCTAssertEqual(layout.items.first { $0.id == second }?.height, layout.canvasHeight)
        layout.rotate([first, second], by: 365)
        XCTAssertEqual(layout.items.first { $0.id == first }?.rotation, 5)

        layout.align([first, second], to: .left)
        let leftEdges = [first, second].compactMap { id in
            layout.items.first { $0.id == id }.map { $0.centerX - $0.width / 2 }
        }
        XCTAssertEqual(leftEdges[0], leftEdges[1], accuracy: 0.000_001)
        for alignment in LightTableAlignment.allCases {
            var aligned = layout
            aligned.align([first, second], to: alignment)
            let values = [first, second].compactMap { id -> Double? in
                guard let item = aligned.items.first(where: { $0.id == id }) else { return nil }
                switch alignment {
                case .left: return item.centerX - item.width / 2
                case .horizontalCenter: return item.centerX
                case .right: return item.centerX + item.width / 2
                case .top: return item.centerY - item.height / 2
                case .verticalCenter: return item.centerY
                case .bottom: return item.centerY + item.height / 2
                }
            }
            XCTAssertEqual(values[0], values[1], accuracy: 0.000_001, alignment.rawValue)
        }
        layout.bringToFront([first])
        XCTAssertEqual(layout.items.max(by: { $0.zIndex < $1.zIndex })?.id, first)
        layout.sendToBack([first])
        XCTAssertEqual(layout.items.min(by: { $0.zIndex < $1.zIndex })?.id, first)

        let preserved = try XCTUnwrap(layout.items.first { $0.id == first })
        let added = photo("Added", width: 1200, height: 500)
        layout.add([added])
        XCTAssertEqual(layout.items.first { $0.id == first }, preserved,
                       "Adding photos must not rearrange the saved canvas")

        let data = try JSONEncoder().encode(layout)
        XCTAssertEqual(try JSONDecoder().decode(LightTableLayout.self, from: data), layout)
        try layout.validated(photoIDs: Set((photos + [added]).map(\.id)))
    }

    func testFormat35PersistenceAndHistoryCompatibility() throws {
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        let photo = photo("One", width: 300, height: 200)
        library.photos = [photo]
        let layout = LightTableLayout(name: "Saved Layout", photos: [photo])
        library.lightTables = [layout]
        var older = library
        older.version = 34
        XCTAssertThrowsError(try older.validateSchema()) {
            XCTAssertEqual($0.localizedDescription, LibraryError.unsupportedVersion.localizedDescription)
        }

        var history = EditHistory()
        history.record(.lightTables([]))
        library.history = history
        let saved = try repository.save(library)
        XCTAssertEqual(saved.version, 35)
        let reopened = try repository.load()
        XCTAssertEqual(reopened.lightTables, [layout])
        XCTAssertEqual(reopened.history?.undo.count, 1)

        var undoHistory = try XCTUnwrap(reopened.history)
        var draft = reopened
        XCTAssertNotNil(undoHistory.step(in: &draft, redoing: false))
        XCTAssertEqual(draft.lightTables, [])
        XCTAssertNotNil(undoHistory.step(in: &draft, redoing: true))
        XCTAssertEqual(draft.lightTables, [layout])
    }

    func testPDFUsesEditedPixelsAndPreservesRecipesOriginalsAndExports() throws {
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("PDF Library"))
        var library = try repository.load()
        let sources = [try image("Wide.png", width: 96, height: 40,
                                 colour: CGColor(red: 0.9, green: 0.1, blue: 0.05, alpha: 1)),
                       try image("Tall.png", width: 36, height: 90,
                                 colour: CGColor(red: 0.05, green: 0.85, blue: 0.1, alpha: 1)),
                       try image("Square.png", width: 64, height: 64,
                                 colour: CGColor(red: 0.05, green: 0.1, blue: 0.9, alpha: 1))]
        for source in sources { XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library)) }
        library.photos[0].adjustments.exposure = 0.35
        library.photos[1].adjustments.quarterTurns = 1
        library = try repository.save(library)
        let recipes = library.photos.map(\.adjustments)
        let originals = try library.photos.map { try Data(contentsOf: repository.availableOriginalURL($0)) }
        var exportOptions = ExportOptions()
        exportOptions.format = .png
        let exports = try library.photos.enumerated().map { index, photo -> Data in
            let url = temporary.appendingPathComponent("Before-\(index).png")
            try Renderer.export(photo, repository: repository, to: url, options: exportOptions)
            return try Data(contentsOf: url)
        }

        var layout = LightTableLayout(name: "Mixed Proof", photos: library.photos)
        layout.rotate([layout.items[0].id], by: 12)
        layout.bringToFront([layout.items[0].id])
        let data = try LightTableOutput.pdfData(layout: layout, photos: library.photos,
                                                repository: repository)
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        let document = try XCTUnwrap(CGPDFDocument(provider))
        XCTAssertEqual(document.numberOfPages, 1)
        let page = try XCTUnwrap(document.page(at: 1))
        XCTAssertEqual(page.getBoxRect(.mediaBox).width, layout.canvasWidth, accuracy: 0.01)
        XCTAssertEqual(page.getBoxRect(.mediaBox).height, layout.canvasHeight, accuracy: 0.01)
        let rendered = try renderedPixels(page)
        XCTAssertGreaterThan(rendered.max() ?? 0, 150, "The PDF must contain rendered photographs")

        let destination = temporary.appendingPathComponent("Light Table.pdf")
        try LightTableOutput.writePDF(layout: layout, photos: library.photos,
                                      repository: repository, to: destination)
        XCTAssertGreaterThan(try Data(contentsOf: destination).count, 500)
        let reopened = try repository.load()
        XCTAssertEqual(reopened.photos.map(\.adjustments), recipes)
        for (index, photo) in reopened.photos.enumerated() {
            XCTAssertEqual(try Data(contentsOf: repository.availableOriginalURL(photo)), originals[index])
            let url = temporary.appendingPathComponent("After-\(index).png")
            try Renderer.export(photo, repository: repository, to: url, options: exportOptions)
            XCTAssertEqual(try Data(contentsOf: url), exports[index])
        }
    }

    private func photo(_ name: String, width: Int, height: Int) -> Photo {
        Photo(filename: "\(name).png", originalName: "\(name).png", projectID: nil,
              width: width, height: height, camera: "", captureDate: "", sha256: name)
    }

    private func image(_ name: String, width: Int, height: Int, colour: CGColor) throws -> URL {
        let url = temporary.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }

    private func renderedPixels(_ page: CGPDFPage) throws -> [UInt8] {
        let width = 320, height = 200
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.concatenate(page.getDrawingTransform(.mediaBox,
            rect: CGRect(x: 0, y: 0, width: width, height: height),
            rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return pixels
    }
}
