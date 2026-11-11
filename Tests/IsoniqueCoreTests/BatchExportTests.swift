import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testBatchExportResolvesCaseAndUnicodeCollisionsForImagesAndSidecars() throws {
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Batch Library"))
        var library = try repository.load()
        let png = try fixture("Image.png")
        let pngSource = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(pngSource, 0, nil))
        let jpeg = temporary.appendingPathComponent("Image.jpg")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(jpeg as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(writer, pixels, nil)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        XCTAssertTrue(try repository.importPhoto(png, projectID: nil, into: &library))
        XCTAssertTrue(try repository.importPhoto(jpeg, projectID: nil, into: &library))

        var first = library.photos[0]
        var second = library.photos[1]
        var third = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        var fourth = try XCTUnwrap(library.createVersion(of: first.id, from: .current))
        first.versionName = "Café"
        second.versionName = "CAFE\u{301}"
        third.versionName = "café-2"
        fourth.versionName = "Cafe\u{301}"
        let photos = [first, second, third, fourth]

        var options = ExportOptions()
        options.format = .original
        options.filenameTemplate = "{version}"
        let withoutSidecars = try BatchExport.plan(photos: photos, projects: [], options: options)
        XCTAssertEqual(withoutSidecars.entries.map(\.filename), ["Café.png", "CAFE\u{301}.jpg", "café-2.png", "Cafe\u{301}-3.png"])

        options.xmpSidecar = true
        let preview = try BatchExport.plan(photos: photos, projects: [], options: options)
        XCTAssertEqual(preview.entries.map(\.filename), ["Café.png", "CAFE\u{301}-2.jpg", "café-2-2.png", "Cafe\u{301}-3.png"])
        XCTAssertEqual(preview.entries.compactMap(\.sidecarFilename), ["Café.xmp", "CAFE\u{301}-2.xmp", "café-2-2.xmp", "Cafe\u{301}-3.xmp"])
        let folder = temporary.appendingPathComponent("Batch Export")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        var written = 0
        try preview.write(to: folder, repository: repository) { written += 1 }
        XCTAssertEqual(written, photos.count)
        let expectedNames = Set(preview.entries.flatMap { [$0.filename, $0.sidecarFilename].compactMap { $0 } })
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), expectedNames)
        for entry in preview.entries {
            let copy = folder.appendingPathComponent(entry.filename)
            XCTAssertEqual(try Data(contentsOf: copy), try Data(contentsOf: repository.availableOriginalURL(entry.photo)))
            let sidecar = folder.appendingPathComponent(try XCTUnwrap(entry.sidecarFilename))
            XCTAssertNotNil(try CGImageMetadataCreateFromXMPData(Data(contentsOf: sidecar) as CFData))
        }
        XCTAssertThrowsError(try preview.write(to: folder, repository: repository))
    }

    func testBatchExportKeepsOldPresetsAndRoundTripsNewTemplates() throws {
        let oldPreset = Data("""
        {"id":"3DE46596-9BA8-7223-8736-0BBA2B3260BA","name":"Client TIFF",
         "options":{"format":"TIFF","quality":0.8,"maxDimension":24,"exif":true,"iptc":false,"gps":true}}
        """.utf8)
        let old = try JSONDecoder().decode(ExportPreset.self, from: oldPreset)
        XCTAssertNil(old.options.filenameTemplate)
        XCTAssertNil(old.options.tiffCompression)
        XCTAssertEqual(old.options.format, .tiff)
        XCTAssertEqual(old.options.quality, 0.8)
        XCTAssertEqual(old.options.maxDimension, 24)
        XCTAssertTrue(old.options.exif && old.options.gps)
        let project = Collection(name: "Client/Studio")
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Preset Library"))
        var library = try repository.load()
        library.projects.append(project)
        XCTAssertTrue(try repository.importPhoto(fixture("Catalogue.png"), projectID: project.id, into: &library))
        var photo = library.photos[0]
        photo.sourceName = "Camera.PNG"
        photo.captureDate = "2024:08:05 12:30:00"
        var version = try XCTUnwrap(library.createVersion(of: photo.id, from: .current))
        version.captureDate = photo.captureDate
        version.sourceName = photo.sourceName
        version.versionName = "Alternate"
        let photos = [photo, version]
        let legacy = try BatchExport.plan(photos: photos, projects: [project], options: old.options)
        XCTAssertEqual(legacy.entries.map(\.filename), ["1-Catalogue.tiff", "2-Alternate.tiff"])

        var options = old.options
        options.tiffCompression = .lzw
        options.filenameTemplate = "{project}-{year}{month}{day}-{sequence}-{original}-{catalogue}-{version}"
        options.xmpSidecar = true
        let new = ExportPreset(name: old.name, options: options)
        let reopened = try JSONDecoder().decode(ExportPreset.self, from: JSONEncoder().encode(new))
        XCTAssertEqual(reopened.options, options)
        let custom = try BatchExport.plan(photos: photos, projects: [project], options: reopened.options)
        XCTAssertEqual(custom.entries.map(\.filename), [
            "Client-Studio-20240805-0001-Camera-Catalogue-Catalogue.tiff",
            "Client-Studio-20240805-0002-Camera-Catalogue-Alternate.tiff"
        ])
        for (plan, directory, compression) in [
            (legacy, "Legacy Export", TIFFCompression.uncompressed),
            (custom, "Custom Export", TIFFCompression.lzw)
        ] {
            let output = temporary.appendingPathComponent(directory)
            try plan.write(to: output, repository: repository)
            let expectedNames = plan.entries.map(\.filename) + plan.entries.compactMap(\.sidecarFilename)
            XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: output.path)), Set(expectedNames))
            for entry in plan.entries {
                let url = output.appendingPathComponent(entry.filename)
                let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
                XCTAssertEqual(CGImageSourceGetType(source) as String?, UTType.tiff.identifier)
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
                let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
                XCTAssertEqual(tiff[kCGImagePropertyTIFFCompression as String] as? Int, compression.imageIOValue)
                let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
                XCTAssertEqual(image.width, 24)
                XCTAssertEqual(image.height, 18)
            }
        }
    }

    func testTIFFCompressionChoicesRoundTripPixelsAndPresets() throws {
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("TIFF Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(fixture("Compression Source.png"), projectID: nil, into: &library))
        let photo = try XCTUnwrap(library.photos.first)
        let originalURL = try repository.availableOriginalURL(photo)
        let originalData = try Data(contentsOf: originalURL)
        let original = try Renderer.render(originalURL, adjustments: photo.adjustments)
        let expectedPixels = try rgba8Pixels(original)

        for compression in TIFFCompression.allCases {
            var options = ExportOptions()
            options.format = .tiff
            options.tiffCompression = compression
            let preset = ExportPreset(name: compression.rawValue, options: options)
            let reopened = try JSONDecoder().decode(ExportPreset.self, from: JSONEncoder().encode(preset))
            XCTAssertEqual(reopened.options, options)

            let output = temporary.appendingPathComponent("\(compression.rawValue).tiff")
            try Renderer.export(photo, repository: repository, to: output, options: reopened.options)
            let source = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
            let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any])
            let tiff = try XCTUnwrap(properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any])
            XCTAssertEqual(tiff[kCGImagePropertyTIFFCompression as String] as? Int, compression.imageIOValue)
            let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            XCTAssertEqual(try rgba8Pixels(decoded), expectedPixels, compression.rawValue)
        }
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
    }

    func testHEIFPresetBatchNameAndFullSizePreviewConsistency() throws {
        let source = temporary.appendingPathComponent("HEIF Source.png")
        try writePattern(to: source)
        let repository = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("HEIF Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        var photo = try XCTUnwrap(library.photos.first)
        photo.adjustments.brightness = 0.08
        let originalURL = try repository.availableOriginalURL(photo)
        let originalData = try Data(contentsOf: originalURL)

        var options = ExportOptions()
        options.format = .heif
        options.quality = 1
        options.filenameTemplate = "{version}"
        let preset = ExportPreset(name: "HEIF Full Quality", options: options)
        let reopened = try JSONDecoder().decode(ExportPreset.self, from: JSONEncoder().encode(preset))
        XCTAssertEqual(reopened.options, options)
        let plan = try BatchExport.plan(photos: [photo], projects: [], options: reopened.options)
        XCTAssertEqual(plan.entries.map(\.filename), ["HEIF Source.heic"])

        let folder = temporary.appendingPathComponent("HEIF Export")
        try plan.write(to: folder, repository: repository)
        let output = folder.appendingPathComponent("HEIF Source.heic")
        let exported = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
        XCTAssertEqual(CGImageSourceGetType(exported) as String?, UTType.heic.identifier)
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(exported, 0, nil))
        let preview = try Renderer.render(originalURL, adjustments: photo.adjustments)
        XCTAssertEqual(decoded.width, preview.width)
        XCTAssertEqual(decoded.height, preview.height)
        let differences = zip(try rgba8Pixels(decoded), try rgba8Pixels(preview)).map {
            abs(Int($0.0) - Int($0.1))
        }
        XCTAssertLessThan(Double(differences.reduce(0, +)) / Double(differences.count), 4)
        XCTAssertLessThanOrEqual(try XCTUnwrap(differences.max()), 48)

        options.quality = 0.2
        let lowQuality = temporary.appendingPathComponent("HEIF Low Quality.heic")
        try Renderer.export(photo, repository: repository, to: lowQuality, options: options)
        XCTAssertNotEqual(try Data(contentsOf: lowQuality), try Data(contentsOf: output))
        XCTAssertEqual(try Data(contentsOf: originalURL), originalData)
    }

    func testBatchExportRejectsUnsafeAndOverlongFilenamesDuringPreview() throws {
        var photo = Photo(filename: "camera.jpg", originalName: "Camera.jpg", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "image")
        photo.versionName = String(repeating: "é", count: 70)
        var options = ExportOptions()
        for pattern in ["../{version}", "{missing}", "{version", "~hidden", "{version}{version}{version}"] {
            options.filenameTemplate = pattern
            XCTAssertThrowsError(try BatchExport.plan(photos: [photo], projects: [], options: options), pattern)
        }

        let longStem = String(repeating: "é", count: 125) + "x"
        options.filenameTemplate = longStem
        var second = photo
        second.id = UUID()
        let preview = try BatchExport.plan(photos: [photo, second], projects: [], options: options)
        XCTAssertEqual(preview.entries.map(\.filename), [longStem + ".jpg", String(repeating: "é", count: 124) + "-2.jpg"])
    }
}

private func rgba8Pixels(_ image: CGImage) throws -> [UInt8] {
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = try XCTUnwrap(CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return pixels
}

private func writePattern(to url: URL) throws {
    let context = try XCTUnwrap(CGContext(
        data: nil,
        width: 64,
        height: 48,
        bitsPerComponent: 8,
        bytesPerRow: 64 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
    ))
    let colours: [CGColor] = [
        CGColor(red: 0.12, green: 0.25, blue: 0.82, alpha: 1),
        CGColor(red: 0.88, green: 0.18, blue: 0.22, alpha: 1),
        CGColor(red: 0.16, green: 0.76, blue: 0.32, alpha: 1),
        CGColor(red: 0.74, green: 0.68, blue: 0.12, alpha: 1)
    ]
    for (index, colour) in colours.enumerated() {
        context.setFillColor(colour)
        context.fill(CGRect(x: CGFloat(index % 2) * 32, y: CGFloat(index / 2) * 24, width: 32, height: 24))
    }
    let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(writer, try XCTUnwrap(context.makeImage()), nil)
    XCTAssertTrue(CGImageDestinationFinalize(writer))
}
