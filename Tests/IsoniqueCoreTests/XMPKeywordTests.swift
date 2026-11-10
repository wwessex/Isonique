import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testXMPKeywordSidecarRoundTripsTwoLondonPathsWithFlatIPTC() throws {
        let source = try fixture()
        let sourceHash = try LibraryRepository.digest(source)
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("Source Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        var photo = try XCTUnwrap(library.photos.first)
        let places = try XCTUnwrap(KeywordPath(["Places", "London"]))
        let people = try XCTUnwrap(KeywordPath(["People & family", "London"]))
        photo.keywordPaths = [places, people]
        photo.caption = "A < B & C"
        photo.rating = 4

        for format in [ExportFormat.jpeg, .original] {
            photo.keywords = format == .original ? "London, Café, Film" : "Café, Film"
            var options = ExportOptions()
            options.format = format
            options.iptc = true
            options.xmpSidecar = true
            let suffix = format == .original ? "png" : format.suffix
            let image = temporary.appendingPathComponent("Export-\(format.id).\(suffix)")
            let sidecar = image.deletingPathExtension().appendingPathExtension("xmp")
            try Renderer.export(photo, repository: repository, to: image, options: options)

            let packet = try String(contentsOf: sidecar, encoding: .utf8)
            XCTAssertTrue(packet.contains("Places|London"))
            XCTAssertTrue(packet.contains("People &amp; family|London"))
            if format == .original {
                XCTAssertEqual(try LibraryRepository.digest(image), sourceHash)
            } else {
                let rendered = try XCTUnwrap(CGImageSourceCreateWithURL(image as CFURL, nil))
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(rendered, 0, nil) as? [String: Any])
                let iptc = try XCTUnwrap(properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any])
                XCTAssertEqual(iptc[kCGImagePropertyIPTCKeywords as String] as? [String], ["Café", "Film", "London"])
            }

            let restored = try LibraryRepository(root: temporary.appendingPathComponent("Library-\(format.id)"))
            var imported = try restored.load()
            var importOptions = ImportOptions()
            importOptions.readSidecars = true
            XCTAssertTrue(try restored.importPhoto(image, projectID: nil, into: &imported, options: importOptions))
            let catalogue = try restored.load()
            let roundTripped = try XCTUnwrap(catalogue.photos.first)
            XCTAssertEqual(catalogue.version, 10)
            XCTAssertEqual(roundTripped.keywordPaths, [places, people])
            XCTAssertEqual(roundTripped.keywords, photo.keywords)
            XCTAssertEqual(roundTripped.caption, photo.caption)
            XCTAssertEqual(roundTripped.rating, photo.rating)
        }
        XCTAssertEqual(try LibraryRepository.digest(source), sourceHash)
        XCTAssertEqual(try LibraryRepository.digest(repository.originalURL(photo)), sourceHash)

        // Existing export presets lack the sidecar key and still export only the requested image.
        let legacyPreset = Data(#"{"format":"JPEG","quality":0.95,"maxDimension":0,"exif":false,"iptc":true,"gps":false}"#.utf8)
        let legacy = try JSONDecoder().decode(ExportOptions.self, from: legacyPreset)
        let iptcOnly = temporary.appendingPathComponent("IPTC Only.jpg")
        photo.keywords = "Film"
        try Renderer.export(photo, repository: repository, to: iptcOnly, options: legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: iptcOnly.deletingPathExtension().appendingPathExtension("xmp").path))
        let legacyLibrary = try LibraryRepository(root: temporary.appendingPathComponent("Legacy Library"))
        var legacyImport = try legacyLibrary.load()
        XCTAssertTrue(try legacyLibrary.importPhoto(iptcOnly, projectID: nil, into: &legacyImport))
        XCTAssertEqual(legacyImport.photos.first?.keywords, "Film, London")
        XCTAssertNil(legacyImport.photos.first?.keywordPaths)
    }

    func testXMPKeywordImportUsesNamespaceAndLeavesAbsentFieldsAlone() throws {
        let image = try fixture()
        let sidecar = image.deletingPathExtension().appendingPathExtension("xmp")
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(image, projectID: nil, into: &library))
        var photo = try XCTUnwrap(library.photos.first)
        photo.keywords = "Legacy, London"
        let people = try XCTUnwrap(KeywordPath(["People", "London"]))
        let places = try XCTUnwrap(KeywordPath(["Places", "London"]))
        let external = """
        <r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
          <r:Description r:about="" xmlns:terms="http://ns.adobe.com/lightroom/1.0/">
            <terms:hierarchicalSubject><r:Bag>
              <r:li>Places|London</r:li><r:li>People|London</r:li><r:li>places|london</r:li>
            </r:Bag></terms:hierarchicalSubject>
          </r:Description>
          <r:Description r:about="" xmlns:score="http://ns.adobe.com/xap/1.0/" score:Rating="3"/>
        </r:RDF>
        """
        try external.write(to: sidecar, atomically: true, encoding: .utf8)
        let record = try XCTUnwrap(MetadataXML.read(sidecar).first)
        photo = record.applying(to: photo)
        XCTAssertEqual(photo.keywordPaths, [places, people])
        XCTAssertEqual(photo.keywords, "Legacy, London")
        XCTAssertEqual(photo.rating, 3)

        // Read the same RDF from an image packet without requiring an adjacent file.
        let packet = #"<x:xmpmeta xmlns:x="adobe:ns:meta/">"# + external + "</x:xmpmeta>"
        let metadata = try XCTUnwrap(CGImageMetadataCreateFromXMPData(Data(packet.utf8) as CFData))
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(image as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
        let embedded = temporary.appendingPathComponent("Embedded.tiff")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(embedded as CFURL, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImageAndMetadata(destination, pixels, metadata, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        XCTAssertTrue(try repository.importPhoto(embedded, projectID: nil, into: &library))
        XCTAssertEqual(library.photos.last?.keywordPaths, [places, people])

        let flat = """
        <r:RDF xmlns:r="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <r:Description r:about=""><dc:subject><r:Bag><r:li>Flat only</r:li></r:Bag></dc:subject></r:Description>
        </r:RDF>
        """
        try flat.write(to: sidecar, atomically: true, encoding: .utf8)
        photo = try XCTUnwrap(MetadataXML.read(sidecar).first).applying(to: photo)
        XCTAssertEqual(photo.keywords, "Flat only")
        XCTAssertEqual(photo.keywordPaths, [places, people])

        let malformed = external.replacingOccurrences(of: "Places|London", with: "Places||London")
        try malformed.write(to: sidecar, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try MetadataXML.read(sidecar))
        let empty = external.replacingOccurrences(
            of: "<r:li>Places|London</r:li><r:li>People|London</r:li><r:li>places|london</r:li>", with: ""
        )
        try empty.write(to: sidecar, atomically: true, encoding: .utf8)
        XCTAssertNil(try XCTUnwrap(MetadataXML.read(sidecar).first).applying(to: photo).keywordPaths)
    }

    func testXMPKeywordExportProtectsExistingSidecarsAndRejectsAmbiguousPaths() throws {
        let source = try fixture()
        let repository = try LibraryRepository(root: temporary.appendingPathComponent("Library"))
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library))
        var photo = try XCTUnwrap(library.photos.first)
        var options = ExportOptions()
        options.xmpSidecar = true
        XCTAssertEqual(try JSONDecoder().decode(ExportOptions.self, from: JSONEncoder().encode(options)), options)
        let image = temporary.appendingPathComponent("Export.jpg")
        let sidecar = image.deletingPathExtension().appendingPathExtension("xmp")
        let existing = Data("Existing sidecar".utf8)
        try existing.write(to: sidecar)
        XCTAssertThrowsError(try Renderer.export(photo, repository: repository, to: image, options: options))
        XCTAssertEqual(try Data(contentsOf: sidecar), existing)
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: image.path))

        try fm.removeItem(at: sidecar)
        let missing = temporary.appendingPathComponent("Missing.xmp")
        try fm.createSymbolicLink(at: sidecar, withDestinationURL: missing)
        XCTAssertThrowsError(try Renderer.export(photo, repository: repository, to: image, options: options))
        XCTAssertEqual(try fm.destinationOfSymbolicLink(atPath: sidecar.path), missing.path)
        XCTAssertFalse(fm.fileExists(atPath: image.path))
        XCTAssertFalse(fm.fileExists(atPath: missing.path))

        try fm.removeItem(at: sidecar)
        photo.keywordPaths = [try XCTUnwrap(KeywordPath(["Two | Names", "London"]))]
        XCTAssertThrowsError(try Renderer.export(photo, repository: repository, to: image, options: options)) { error in
            guard case XMPMetadata.Failure.unrepresentablePath = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertFalse(fm.fileExists(atPath: image.path))
        XCTAssertFalse(fm.fileExists(atPath: sidecar.path))

        // The sidecar fits the filesystem's name limit, while the longer TIFF suffix does not.
        photo.keywordPaths = nil
        options.format = .tiff
        let longName = String(repeating: "a", count: 251)
        let unwritableImage = temporary.appendingPathComponent(longName + ".tiff")
        let unwrittenSidecar = temporary.appendingPathComponent(longName + ".xmp")
        XCTAssertThrowsError(try Renderer.export(photo, repository: repository, to: unwritableImage, options: options))
        XCTAssertFalse(fm.fileExists(atPath: unwrittenSidecar.path))
    }
}
