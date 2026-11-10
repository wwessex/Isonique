import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testIPTCMetadataExportsAndRoundTripsWithoutChangingOriginal() throws {
        let plain = try fixture()
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(plain as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        let image = temporary.appendingPathComponent("Original.jpg")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(image as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let input = IPTCMetadata(title: "Embedded", creators: ["First Creator", "Second Creator"],
                                 copyright: "Old Copyright", credit: "Old Credit")
        var iptc: [String: Any] = [kCGImagePropertyIPTCKeywords as String: ["Existing keyword"]]
        input.writing(to: &iptc)
        CGImageDestinationAddImage(writer, pixels, [kCGImagePropertyIPTCDictionary as String: iptc] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        let hash = try LibraryRepository.digest(image)
        let repo = try LibraryRepository(root: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        XCTAssertTrue(try repo.importPhoto(image, projectID: nil, into: &library))
        var photo = try XCTUnwrap(library.photos.first)
        XCTAssertEqual(photo.iptc, input)
        XCTAssertEqual(library.version, 11)

        // Earlier catalogues left these fields in the original. An untouched export still carries them.
        photo.iptc = nil
        XCTAssertEqual(repo.embeddedIPTC(for: photo), input)
        let legacy = temporary.appendingPathComponent("Legacy.jpg")
        var options = ExportOptions()
        options.iptc = true
        try Renderer.export(photo, repository: repo, to: legacy, options: options)
        let legacyRepo = try LibraryRepository(root: temporary.appendingPathComponent("Legacy Library"))
        var legacyLibrary = try legacyRepo.load()
        XCTAssertTrue(try legacyRepo.importPhoto(legacy, projectID: nil, into: &legacyLibrary))
        XCTAssertEqual(legacyLibrary.photos.first?.iptc, input)

        let edits = IPTCMetadata(title: "The Harbour & the Sea", creators: ["Ng, Alex", "Jo Weiß"],
                                 copyright: "© 2026 Atelier", credit: "")
        photo.iptc = edits
        options.xmpSidecar = true
        for format in [ExportFormat.jpeg, .original] {
            options.format = format
            let output = temporary.appendingPathComponent("Output-\(format.id).jpg")
            try Renderer.export(photo, repository: repo, to: output, options: options)
            let sidecar = output.deletingPathExtension().appendingPathExtension("xmp")
            let record = try XCTUnwrap(MetadataXML.read(sidecar).first)
            XCTAssertEqual(record.iptc, edits)
            let packet = try String(contentsOf: sidecar, encoding: .utf8)
            XCTAssertTrue(packet.contains("<rdf:Seq>"))
            XCTAssertTrue(packet.contains("<dc:rights>"))
            if format == .original {
                XCTAssertEqual(try LibraryRepository.digest(output), hash)
            } else {
                let exported = try XCTUnwrap(CGImageSourceCreateWithURL(output as CFURL, nil))
                let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(exported, 0, nil) as? [String: Any])
                let iptc = try XCTUnwrap(properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any])
                XCTAssertEqual(iptc[kCGImagePropertyIPTCObjectName as String] as? String, edits.title)
                XCTAssertEqual(iptc[kCGImagePropertyIPTCByline as String] as? [String], edits.creators)
                XCTAssertEqual(iptc[kCGImagePropertyIPTCCopyrightNotice as String] as? String, edits.copyright)
                XCTAssertNil(iptc[kCGImagePropertyIPTCCredit as String])
                XCTAssertEqual(iptc[kCGImagePropertyIPTCKeywords as String] as? [String], ["Existing keyword"])
            }
            let target = try LibraryRepository(root: temporary.appendingPathComponent("Target-\(format.id)"))
            var imported = try target.load()
            var importOptions = ImportOptions()
            importOptions.readSidecars = true
            XCTAssertTrue(try target.importPhoto(output, projectID: nil, into: &imported, options: importOptions))
            XCTAssertEqual(try target.load().photos.first?.iptc, edits)
        }
        XCTAssertEqual(try LibraryRepository.digest(image), hash)
        XCTAssertEqual(try LibraryRepository.digest(repo.originalURL(photo)), hash)
    }

    func testIPTCOnlySidecarLeavesOmittedFieldsAndCanClearOne() throws {
        let sidecar = temporary.appendingPathComponent("Metadata.xmp")
        let packet = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:ps="http://ns.adobe.com/photoshop/1.0/" ps:Credit="News Desk"
                             xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:title><rdf:Alt><rdf:li xml:lang="fr">Autre</rdf:li><rdf:li xml:lang="x-default">Default</rdf:li></rdf:Alt></dc:title>
              <dc:creator><rdf:Seq/></dc:creator>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try packet.write(to: sidecar, atomically: true, encoding: .utf8)
        let record = try XCTUnwrap(MetadataXML.read(sidecar).first)
        var photo = Photo(filename: "image.jpg", originalName: "image.jpg", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "")
        photo.iptc = IPTCMetadata(creators: ["Creator"], copyright: "Keep this")
        photo.caption = "Keep caption"
        let updated = record.applying(to: photo)
        XCTAssertEqual(updated.iptc, IPTCMetadata(title: "Default", creators: [], copyright: "Keep this", credit: "News Desk"))
        XCTAssertEqual(updated.caption, photo.caption)

        let clear = IPTCMetadata(title: "", creators: [], copyright: "", credit: "")
        try XMPMetadata.encode(photo, iptc: clear).write(to: sidecar)
        XCTAssertEqual(try MetadataXML.read(sidecar).first?.applying(to: photo).iptc, clear)
        let attributeClear = packet.replacingOccurrences(of: "ps:Credit=\"News Desk\"", with: "ps:Credit=\"\"")
        try attributeClear.write(to: sidecar, atomically: true, encoding: .utf8)
        XCTAssertEqual(try MetadataXML.read(sidecar).first?.iptc?.credit, "")
    }

    func testIPTCMergeKeepsIndependentFieldsAndPreservesOlderSourceCompatibility() throws {
        let original = Photo(filename: "image.jpg", originalName: "image.jpg", projectID: nil,
                             width: 32, height: 24, camera: "", captureDate: "", sha256: "")
        var current = original
        current.iptc = IPTCMetadata(title: "Current title", copyright: "Copyright")
        var incoming = original
        incoming.iptc = IPTCMetadata(title: "Incoming title", credit: "Incoming credit")
        let baseline = ProjectPhotoMergeValues(original)
        let merge = baseline.merging(current, with: incoming, prefer: .current, representedAlbums: [])
        XCTAssertEqual(merge.conflicts, ["Title"])
        XCTAssertEqual(merge.photo.iptc, IPTCMetadata(title: "Current title", copyright: "Copyright", credit: "Incoming credit"))
        XCTAssertEqual(baseline.merging(current, with: incoming, prefer: .incoming, representedAlbums: []).photo.iptc?.title,
                       "Incoming title")
        XCTAssertEqual(ProjectPhotoMergeValues.mergingEditableValues(current, with: original, baseline: nil, prefer: .incoming).photo.iptc,
                       current.iptc)
    }
}
