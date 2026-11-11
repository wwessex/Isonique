import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testWatermarkControlsPersistAndPlaceText() throws {
        let oldPreset = Data("""
        {"id":"3DE46596-9BA8-7223-8736-0BBA2B3260BA","name":"Older JPEG",
         "options":{"format":"JPEG","quality":0.9,"maxDimension":0,"exif":false,"iptc":false,"gps":false}}
        """.utf8)
        XCTAssertNil(try JSONDecoder().decode(ExportPreset.self, from: oldPreset).options.watermark)

        let source = try watermarkFixture(at: temporary.appendingPathComponent("Watermark Controls.png"))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
            try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil)), 0, nil))
        let base = try watermarkPixels(image)
        var options = ExportOptions()
        options.watermark = WatermarkSettings(text: "© Studio", position: .bottomRight,
                                              opacity: 0.65, scale: 0.08)
        let preset = ExportPreset(name: "Copyright", options: options)
        XCTAssertEqual(try JSONDecoder().decode(ExportPreset.self, from: JSONEncoder().encode(preset)).options,
                       options)

        for position in WatermarkPosition.allCases {
            var settings = try XCTUnwrap(options.watermark)
            settings.position = position
            let rendered = try ExportWatermark.apply(settings, to: image)
            let bounds = try XCTUnwrap(watermarkDifferenceBounds(base, try watermarkPixels(rendered),
                                                                 width: image.width, height: image.height))
            let x = Double(bounds.midX) / Double(image.width)
            let y = Double(bounds.midY) / Double(image.height)
            switch position {
            case .topLeft: XCTAssertLessThan(x, 0.45); XCTAssertLessThan(y, 0.45)
            case .topRight: XCTAssertGreaterThan(x, 0.55); XCTAssertLessThan(y, 0.45)
            case .center: XCTAssertEqual(x, 0.5, accuracy: 0.12); XCTAssertEqual(y, 0.5, accuracy: 0.12)
            case .bottomLeft: XCTAssertLessThan(x, 0.45); XCTAssertGreaterThan(y, 0.55)
            case .bottomRight: XCTAssertGreaterThan(x, 0.55); XCTAssertGreaterThan(y, 0.55)
            }
        }

        let faint = try ExportWatermark.apply(WatermarkSettings(text: "© Studio", opacity: 0.2, scale: 0.08),
                                                to: image)
        let opaque = try ExportWatermark.apply(WatermarkSettings(text: "© Studio", opacity: 1, scale: 0.08),
                                                 to: image)
        XCTAssertLessThan(watermarkDifferenceTotal(base, try watermarkPixels(faint)),
                          watermarkDifferenceTotal(base, try watermarkPixels(opaque)))
        let small = try ExportWatermark.apply(WatermarkSettings(text: "© Studio", opacity: 1, scale: 0.04),
                                               to: image)
        let large = try ExportWatermark.apply(WatermarkSettings(text: "© Studio", opacity: 1, scale: 0.12),
                                               to: image)
        XCTAssertLessThan(watermarkChangedPixels(base, try watermarkPixels(small)),
                          watermarkChangedPixels(base, try watermarkPixels(large)))
    }

    func testWatermarkBatchPreviewAndEditedFormatsPreserveOriginal() throws {
        let source = try watermarkFixture(at: temporary.appendingPathComponent("Watermark Source.png"))
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Watermark Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        let photo = try XCTUnwrap(library.photos.first)
        let version = try XCTUnwrap(library.createVersion(of: photo.id, from: .current))
        let originalURL = try repository.availableOriginalURL(photo)
        let originalData = try Data(contentsOf: originalURL)
        let settings = WatermarkSettings(text: "© Isonique Test", position: .topRight,
                                         opacity: 0.72, scale: 0.07)
        let base = try Renderer.render(originalURL, adjustments: photo.adjustments)
        let preview = try ExportWatermark.apply(settings, to: base)
        let previewPixels = try watermarkPixels(preview)

        for format in [ExportFormat.jpeg, .png, .tiff, .heif] {
            var options = ExportOptions()
            options.format = format
            options.quality = 1
            options.watermark = settings
            let output = temporary.appendingPathComponent("Watermarked.\(format.suffix)")
            try Renderer.export(photo, repository: repository, to: output, options: options)
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
                try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil)), 0, nil))
            XCTAssertGreaterThan(watermarkDifferenceTotal(try watermarkPixels(base),
                                                          try watermarkPixels(decoded)), 0)
            if format == .png { XCTAssertEqual(try watermarkPixels(decoded), previewPixels) }
        }

        var batchOptions = ExportOptions()
        batchOptions.format = .png
        batchOptions.watermark = settings
        let plan = try BatchExport.plan(photos: [photo, version], projects: [], options: batchOptions)
        let folder = temporary.appendingPathComponent("Watermarked Batch")
        try plan.write(to: folder, repository: repository)
        XCTAssertEqual(plan.entries.count, 2)
        for entry in plan.entries {
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(
                try XCTUnwrap(CGImageSourceCreateWithURL(folder.appendingPathComponent(entry.filename) as CFURL, nil)),
                0, nil))
            XCTAssertEqual(try watermarkPixels(decoded), previewPixels)
        }

        var originalOptions = batchOptions
        originalOptions.format = .original
        let copy = temporary.appendingPathComponent("Watermarked Original.png")
        try Renderer.export(photo, repository: repository, to: copy, options: originalOptions)
        XCTAssertEqual(try Data(contentsOf: copy), originalData)
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
    }
}

private func watermarkFixture(at url: URL) throws -> URL {
    let context = try XCTUnwrap(CGContext(data: nil, width: 240, height: 160, bitsPerComponent: 8,
                                         bytesPerRow: 240 * 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                             CGBitmapInfo.byteOrder32Big.rawValue))
    context.setFillColor(CGColor(red: 0.08, green: 0.12, blue: 0.18, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
    context.setFillColor(CGColor(red: 0.22, green: 0.38, blue: 0.56, alpha: 1))
    context.fill(CGRect(x: 36, y: 30, width: 72, height: 92))
    let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(writer))
    return url
}

private func watermarkPixels(_ image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height,
                                         bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                             CGBitmapInfo.byteOrder32Big.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

private func watermarkDifferenceBounds(_ first: [UInt8], _ second: [UInt8], width: Int,
                                       height: Int) -> CGRect? {
    var minimumX = width
    var minimumY = height
    var maximumX = -1
    var maximumY = -1
    for pixel in 0..<(width * height) {
        let offset = pixel * 4
        guard first[offset..<(offset + 4)] != second[offset..<(offset + 4)] else { continue }
        let x = pixel % width
        let y = pixel / width
        minimumX = min(minimumX, x)
        minimumY = min(minimumY, y)
        maximumX = max(maximumX, x)
        maximumY = max(maximumY, y)
    }
    guard maximumX >= minimumX, maximumY >= minimumY else { return nil }
    return CGRect(x: minimumX, y: minimumY, width: maximumX - minimumX + 1,
                  height: maximumY - minimumY + 1)
}

private func watermarkDifferenceTotal(_ first: [UInt8], _ second: [UInt8]) -> Int {
    zip(first, second).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
}

private func watermarkChangedPixels(_ first: [UInt8], _ second: [UInt8]) -> Int {
    stride(from: 0, to: min(first.count, second.count), by: 4).reduce(0) { count, offset in
        count + (first[offset..<(offset + 4)] == second[offset..<(offset + 4)] ? 0 : 1)
    }
}
