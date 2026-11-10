import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testReusableMetadataPresetPreservesImportOptionsAndRespectsSidecarPrecedence() throws {
        let source = try fixture()
        let original = try Data(contentsOf: source)
        let sidecar = source.deletingPathExtension().appendingPathExtension("xmp")
        let packet = """
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description xmlns:ps="http://ns.adobe.com/photoshop/1.0/" ps:Credit="Sidecar Credit"/>
          </rdf:RDF>
        </x:xmpmeta>
        """
        try packet.write(to: sidecar, atomically: true, encoding: .utf8)

        let old = Data(#"{"pairing":"Link RAW + JPEG","prefix":"Job","caption":"Caption default","keywords":"Base, studio","rating":4,"applyMetadata":true,"readSidecars":true}"#.utf8)
        var options = try JSONDecoder().decode(ImportOptions.self, from: old)
        XCTAssertNil(options.reusableMetadata)
        options.reusableMetadata = MetadataPreset(name: "Reusable", values: MetadataPresetValues(
            keywordMode: .append, keywords: "Studio, Archive", iptc: IPTCMetadata(title: "Preset title", credit: "Preset credit")))
        let combined = ImportPreset(name: "Named import setup", options: options)
        let decoded = try JSONDecoder().decode(ImportPreset.self, from: JSONEncoder().encode(combined))
        XCTAssertEqual(decoded.options, options)

        let repo = try LibraryRepository(root: temporary.appendingPathComponent("Library"))
        var library = try repo.load()
        XCTAssertTrue(try repo.importPhoto(source, projectID: nil, into: &library, options: decoded.options))
        let photo = try XCTUnwrap(repo.load().photos.first)
        XCTAssertEqual(photo.originalName, "Job-" + source.lastPathComponent)
        XCTAssertEqual(photo.caption, "Caption default")
        XCTAssertEqual(photo.keywords, "Base, studio, Archive")
        XCTAssertEqual(photo.rating, 4)
        XCTAssertEqual(photo.iptc, IPTCMetadata(title: "Preset title", credit: "Sidecar Credit"))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
