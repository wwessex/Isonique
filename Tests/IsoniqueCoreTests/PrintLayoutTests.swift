import XCTest
import AppKit
import ImageIO
import UniformTypeIdentifiers
@testable import IsoniqueCore

final class PrintLayoutTests: XCTestCase {
    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniquePrintLayoutTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temporary) }

    func testContactSheetPaginationPageSizeMarginsAndCaptions() throws {
        let photos = (1...13).map { number -> Photo in
            var photo = Photo(filename: "\(number).png", originalName: "Photo-\(number).png", projectID: nil,
                              width: 40, height: 30, camera: "", captureDate: "", sha256: "\(number)")
            photo.versionName = "Proof \(number)"
            photo.caption = "Caption \(number)"
            return photo
        }
        let options = PrintLayoutOptions(pageSize: .a4, orientation: .landscape, marginPoints: 42,
                                         columns: 3, rows: 2, caption: .nameAndCaption)
        let plan = try PrintLayout.plan(photos: photos, options: options)

        XCTAssertEqual(plan.pageSize.width, PrintPageSize.a4.portraitDimensions.height, accuracy: 0.01)
        XCTAssertEqual(plan.pageSize.height, PrintPageSize.a4.portraitDimensions.width, accuracy: 0.01)
        XCTAssertEqual(plan.pages.map(\.cells.count), [6, 6, 1])
        XCTAssertEqual(plan.pages[0].cells[0].caption, "Proof 1\nCaption 1")
        for cell in plan.pages.flatMap(\.cells) {
            XCTAssertGreaterThanOrEqual(cell.frame.minX, 42)
            XCTAssertGreaterThanOrEqual(cell.frame.minY, 42)
            XCTAssertLessThanOrEqual(cell.frame.maxX, plan.pageSize.width - 42 + 0.001)
            XCTAssertLessThanOrEqual(cell.frame.maxY, plan.pageSize.height - 42 + 0.001)
            XCTAssertTrue(cell.frame.contains(cell.imageFrame))
            XCTAssertTrue(cell.frame.contains(cell.captionFrame))
        }
    }

    func testProofLayoutAndPresetRoundTrip() throws {
        var first = Photo(filename: "first.png", originalName: "First.png", projectID: nil,
                          width: 20, height: 10, camera: "", captureDate: "", sha256: "1")
        first.caption = "Client proof"
        let second = Photo(filename: "second.png", originalName: "Second.png", projectID: nil,
                           width: 20, height: 10, camera: "", captureDate: "", sha256: "2")
        let options = PrintLayoutOptions(style: .proof, pageSize: .letter, orientation: .portrait,
                                         marginPoints: 54, columns: 9, rows: 9,
                                         caption: .caption, colourMode: .displayP3)
        let plan = try PrintLayout.plan(photos: [first, second], options: options)
        XCTAssertEqual(plan.pages.map(\.cells.count), [1, 1])
        XCTAssertEqual(plan.pages[0].cells[0].caption, "Client proof")
        XCTAssertEqual(plan.pages[1].cells[0].caption, "")

        let preset = PrintPreset(name: "Studio Proof", options: options)
        XCTAssertEqual(try JSONDecoder().decode(PrintPreset.self, from: JSONEncoder().encode(preset)), preset)
        XCTAssertThrowsError(try PrintLayout.plan(photos: [], options: options)) {
            XCTAssertEqual($0 as? PrintLayoutError, .noPhotos)
        }
    }

    func testPDFPaginationColourModesAndOriginalPreservation() throws {
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        for (index, colour) in [CGColor(red: 0.9, green: 0.08, blue: 0.05, alpha: 1),
                                CGColor(red: 0.05, green: 0.75, blue: 0.15, alpha: 1),
                                CGColor(red: 0.05, green: 0.15, blue: 0.9, alpha: 1)].enumerated() {
            let source = try image(named: "Colour-\(index).png", colour: colour)
            XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        }
        library.photos[0].adjustments.exposure = 0.25
        library.photos[0].caption = "Adjusted red proof"
        library = try repository.save(library)
        let originals = try Dictionary(uniqueKeysWithValues: library.photos.map {
            ($0.id, try Data(contentsOf: repository.availableOriginalURL($0)))
        })
        let options = PrintLayoutOptions(pageSize: .letter, marginPoints: 36, columns: 2, rows: 1,
                                         caption: .nameAndCaption, colourMode: .sRGB)
        let colourPDF = try PrintLayout.pdfData(photos: library.photos, repository: repository, options: options)
        let colourDocument = try pdf(colourPDF)
        XCTAssertEqual(colourDocument.numberOfPages, 2)
        let firstPage = try XCTUnwrap(colourDocument.page(at: 1))
        XCTAssertEqual(firstPage.getBoxRect(.mediaBox).width, 612, accuracy: 0.01)
        XCTAssertEqual(firstPage.getBoxRect(.mediaBox).height, 792, accuracy: 0.01)
        XCTAssertGreaterThan(maximumChannelDifference(in: try renderedPixels(firstPage)), 80)

        var displayP3 = options
        displayP3.colourMode = .displayP3
        let displayP3Data = try PrintLayout.pdfData(photos: library.photos, repository: repository,
                                                     options: displayP3)
        XCTAssertNotEqual(displayP3Data, colourPDF)
        XCTAssertGreaterThan(maximumChannelDifference(in: try renderedPixels(
            try XCTUnwrap(try pdf(displayP3Data).page(at: 1))
        )), 80)

        var monochrome = options
        monochrome.colourMode = .monochrome
        let monochromeDocument = try pdf(PrintLayout.pdfData(photos: library.photos, repository: repository,
                                                               options: monochrome))
        let monochromePage = try XCTUnwrap(monochromeDocument.page(at: 1))
        XCTAssertLessThanOrEqual(maximumChannelDifference(in: try renderedPixels(monochromePage)), 2)

        let destination = temporary.appendingPathComponent("Contact Sheet.pdf")
        try PrintLayout.writePDF(photos: library.photos, repository: repository, options: options, to: destination)
        XCTAssertEqual(try pdf(Data(contentsOf: destination)).numberOfPages, 2)
        XCTAssertThrowsError(try PrintLayout.writePDF(photos: library.photos, repository: repository,
                                                       options: options, to: destination))
        for photo in library.photos {
            XCTAssertEqual(try Data(contentsOf: repository.availableOriginalURL(photo)), originals[photo.id])
        }
        XCTAssertEqual(try repository.load().photos, library.photos)
    }

    private func pdf(_ data: Data) throws -> CGPDFDocument {
        let provider = try XCTUnwrap(CGDataProvider(data: data as CFData))
        return try XCTUnwrap(CGPDFDocument(provider))
    }

    private func renderedPixels(_ page: CGPDFPage) throws -> [UInt8] {
        let bounds = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 0.5
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: width, height: height,
                                              bitsPerComponent: 8, bytesPerRow: width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                                  CGBitmapInfo.byteOrder32Big.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(page.getDrawingTransform(.mediaBox,
                                                      rect: CGRect(x: 0, y: 0, width: width, height: height),
                                                      rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return pixels
    }

    private func maximumChannelDifference(in pixels: [UInt8]) -> Int {
        stride(from: 0, to: pixels.count, by: 4).reduce(0) { result, index in
            let red = Int(pixels[index]), green = Int(pixels[index + 1]), blue = Int(pixels[index + 2])
            return max(result, max(abs(red - green), max(abs(red - blue), abs(green - blue))))
        }
    }

    private func image(named name: String, colour: CGColor) throws -> URL {
        let url = temporary.appendingPathComponent(name)
        let context = try XCTUnwrap(CGContext(data: nil, width: 48, height: 32, bitsPerComponent: 8,
                                              bytesPerRow: 48 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: 48, height: 32))
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil
        ))
        CGImageDestinationAddImage(destination, try XCTUnwrap(context.makeImage()), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return url
    }
}
