import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import IsoniqueCore

extension LibraryTests {
    func testStampUsesInheritedFieldsPreservesMissingFieldsAndPrunesPurgedTargets() throws {
        var source = Photo(filename: "source.jpg", originalName: "source.jpg", projectID: nil,
                           width: 32, height: 24, camera: "", captureDate: "", sha256: "source")
        source.iptc = IPTCMetadata(credit: "")
        let lifted = LiftedSettings(source, embeddedIPTC: IPTCMetadata(title: "Embedded title", creators: ["One", "Two"],
                                                                       credit: "Overridden credit"))
        var first = Photo(filename: "first.jpg", originalName: "first.jpg", projectID: nil,
                          width: 32, height: 24, camera: "", captureDate: "", sha256: "first")
        first.iptc = IPTCMetadata(copyright: "Keep rights", credit: "Clear")
        var second = first
        second.id = UUID()
        second.filename = "second.jpg"
        var library = Library()
        library.photos = [first, second]

        let single = lifted.applying(to: first, groups: [], metadata: [.iptcTitle, .iptcCreator, .iptcCopyright, .iptcCredit])
        XCTAssertEqual(single.iptc, IPTCMetadata(title: "Embedded title", creators: ["One", "Two"],
                                                 copyright: "Keep rights", credit: ""))
        XCTAssertFalse(lifted.includesMetadata(.iptcCopyright))
        let changes = library.stamp(lifted, groups: [], metadata: [.iptcTitle], onto: [first.id, second.id])
        var history = EditHistory()
        history.record(.stamp(changes))
        library.photos.removeFirst()
        history.discardEmptiedTrash(photoIDs: [first.id], originalIDs: [first.originalID])
        XCTAssertNotNil(history.step(in: &library, redoing: false))
        XCTAssertEqual(library.photos, [second])
        XCTAssertNotNil(history.step(in: &library, redoing: true))
        XCTAssertEqual(library.photos.first?.iptc?.title, "Embedded title")
    }

    func testInheritedIPTCReviewsVerifiedSharedOriginalsAndPreservesOverrides() throws {
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        let embedded = IPTCMetadata(title: "Harbour original", creators: ["One", "Two"],
                                    copyright: "Original rights", credit: "Original credit")
        let input = try iptcFixture("Original", fields: embedded)
        let inputBytes = try Data(contentsOf: input)
        let missing = try iptcFixture("Offline", fields: IPTCMetadata(title: "Offline title"))
        let changed = try iptcFixture("Changed", fields: IPTCMetadata(title: "Changed title"))
        let plain = try fixture("Plain.png")
        var draft = try repo.load()
        XCTAssertTrue(try repo.importPhoto(input, projectID: nil, into: &draft))
        var references = ImportOptions()
        references.storage = .referenced
        XCTAssertTrue(try repo.importPhoto(missing, projectID: nil, into: &draft, options: references))
        XCTAssertTrue(try repo.importPhoto(changed, projectID: nil, into: &draft, options: references))
        XCTAssertTrue(try repo.importPhoto(plain, projectID: nil, into: &draft))
        try FileManager.default.removeItem(at: missing)
        try Data("changed after catalogue import".utf8).write(to: changed)
        // Simulate records created before IPTC fields were catalogued.
        draft.photos[0].iptc = IPTCMetadata(copyright: "Keep this", credit: "")
        draft.photos[1].iptc = nil
        draft.photos[2].iptc = nil
        let first = draft.photos[0]
        let version = try XCTUnwrap(draft.createVersion(of: first.id, from: .current))
        let baseline = try repo.save(draft)
        let review = try repo.reviewInheritedIPTC(for: baseline.photos)
        XCTAssertEqual(review.originalCount, 4)
        XCTAssertEqual(review.preview.rows.map(\.id), [first.id, version.id])
        XCTAssertEqual(review.issues.map(\.name), ["Offline.jpg", "Changed.jpg"])
        XCTAssertTrue(review.issues[0].reason.contains("unavailable"))
        XCTAssertTrue(review.issues[1].reason.contains("Integrity"))
        XCTAssertEqual(try repo.load().photos, baseline.photos)

        var stale = baseline
        stale.photos[0].iptc?.title = "Edited after review"
        XCTAssertNil(review.batch.apply(review.preview, to: &stale))
        XCTAssertEqual(stale.photos[0].iptc?.title, "Edited after review")

        var applied = baseline
        let inverse = try XCTUnwrap(review.batch.apply(review.preview, to: &applied))
        XCTAssertEqual(applied.photos[0].iptc, IPTCMetadata(title: "Harbour original", creators: ["One", "Two"],
                                                           copyright: "Keep this", credit: ""))
        XCTAssertEqual(applied.photos.last?.iptc, applied.photos[0].iptc)
        XCTAssertTrue(applied.photos[0].matchesSearchText("Harbour original"))
        XCTAssertFalse(first.matchesSearchText("Harbour original"))
        var history = EditHistory()
        history.record(.batchMetadata(inverse))
        applied.history = history
        _ = try repo.save(applied)
        var reopened = try repo.load()
        var savedHistory = try XCTUnwrap(reopened.history)
        XCTAssertNotNil(savedHistory.step(in: &reopened, redoing: false))
        XCTAssertEqual(reopened.photos, baseline.photos)
        XCTAssertNotNil(savedHistory.step(in: &reopened, redoing: true))
        XCTAssertEqual(reopened.photos, applied.photos)
        XCTAssertEqual(try Data(contentsOf: input), inputBytes)
        XCTAssertEqual(try Data(contentsOf: repo.originalURL(first)), inputBytes)
    }

    func testInheritedIPTCScanHonoursCancellation() async throws {
        let repo = try LibraryRepository.createEmpty(at: temporary.appendingPathComponent("Library"))
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try repo.reviewInheritedIPTC(for: [])
        }
        do {
            _ = try await task.value
            XCTFail("Expected the cancelled scan to stop")
        } catch is CancellationError {
            XCTAssertTrue(try repo.load().photos.isEmpty)
        }
    }

    private func iptcFixture(_ name: String, fields: IPTCMetadata) throws -> URL {
        let source = try fixture(name + ".png")
        let reader = try XCTUnwrap(CGImageSourceCreateWithURL(source as CFURL, nil))
        let pixels = try XCTUnwrap(CGImageSourceCreateImageAtIndex(reader, 0, nil))
        let target = temporary.appendingPathComponent(name + ".jpg")
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(target as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        var iptc: [String: Any] = [:]
        fields.writing(to: &iptc)
        CGImageDestinationAddImage(writer, pixels, [kCGImagePropertyIPTCDictionary as String: iptc] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
        return target
    }
}
