import ImageIO
import IsoniqueCore
import UniformTypeIdentifiers
import XCTest
@testable import Isonique

final class CaptureDateTests: XCTestCase {
    func testPreviewPreservesCameraClockIntervalsAndValidatesInputs() throws {
        let first = photo("First", "2024:03:30 23:59:58")
        let next = photo("Next", "2024:03:31 00:00:01")
        let missing = photo("Missing", "")
        let malformed = photo("Invalid", "2024:02:31 12:00:00")
        let request = CaptureDateCorrection(photos: [missing, first, next, malformed], preferredReferenceID: missing.id)
        XCTAssertEqual(request.referenceName, "First")
        XCTAssertEqual(request.referenceValue, first.captureDate)

        let preview = try request.preview("2024:03:31 23:59:58", preservingIntervals: true)
        XCTAssertEqual(preview.changes.map(\.photoID), [first.id, next.id])
        XCTAssertEqual(preview.changes.map(\.value), ["2024:03:31 23:59:58", "2024:04:01 00:00:01"])
        XCTAssertEqual(preview.skipped, 2)
        XCTAssertTrue(try request.preview(first.captureDate, preservingIntervals: true).changes.isEmpty)

        let assigned = try request.preview("2024:02:29 12:00:00", preservingIntervals: false)
        XCTAssertEqual(assigned.changes.count, 4)
        XCTAssertTrue(assigned.changes.allSatisfy { $0.value == "2024:02:29 12:00:00" })
        XCTAssertEqual(assigned.skipped, 0)
        XCTAssertThrowsError(try request.preview("2023:02:29 12:00:00", preservingIntervals: false))
        XCTAssertThrowsError(try request.preview("2024:01:01 24:00:00", preservingIntervals: false))
        XCTAssertThrowsError(try request.preview("9999:12:31 23:59:59", preservingIntervals: true))
        let undated = CaptureDateCorrection(photos: [missing], preferredReferenceID: nil)
        XCTAssertNil(undated.referenceValue)
        XCTAssertThrowsError(try undated.preview(first.captureDate, preservingIntervals: true))
        XCTAssertEqual(try undated.preview(first.captureDate, preservingIntervals: false).changes.first?.photoID, missing.id)
    }

    @MainActor
    func testBatchCorrectionUpdatesSortAndSmartAlbumWithOnePersistentUndoStep() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        preferences.set(true, forKey: "history.persist")
        let workspace = Workspace(libraryRoot: root.appendingPathComponent("Library"), preferences: preferences)
        let first = photo("First", "2024:03:30 23:00:00")
        let next = photo("Next", "2024:03:30 23:01:00")
        let hidden = photo("Hidden", "2024:03:31 00:00:30")
        var draft = workspace.library
        draft.photos = [first, next, hidden]
        let sibling = try XCTUnwrap(draft.createVersion(of: first.id, from: .current))
        var query = PhotoQuery()
        query.criteria = [PhotoQueryCriterion(field: .captured, comparison: .since, value: "2024-03-31")]
        var rule = SmartAlbumRule(minimumRating: 0, text: "")
        rule.query = query
        var album = Collection(name: "March 31")
        album.rule = rule
        draft.albums = [album]
        XCTAssertTrue(workspace.commit(draft))

        workspace.sort = .captured
        workspace.search = "First"
        workspace.batchMode = true
        workspace.batchSelection = [first.id, hidden.id]
        workspace.openCaptureDateCorrection()
        XCTAssertEqual(workspace.captureDateCorrection?.originalValues, [first.id: first.captureDate])
        workspace.search = ""
        workspace.batchSelection = [first.id, next.id]
        workspace.selection = next.id
        workspace.openCaptureDateCorrection()
        let request = try XCTUnwrap(workspace.captureDateCorrection)
        XCTAssertEqual(request.referenceName, "Next")
        let preview = try request.preview("2024:03:31 00:01:00", preservingIntervals: true)
        XCTAssertTrue(workspace.applyCaptureDateCorrection(preview, for: request))
        XCTAssertEqual(workspace.photos.map(\.id), [sibling.id, first.id, hidden.id, next.id])
        XCTAssertEqual(workspace.history.undo.count, 1)
        XCTAssertEqual(workspace.library.version, 8)
        workspace.scope = "album:\(album.id)"
        XCTAssertEqual(workspace.photos.map(\.id), [first.id, hidden.id, next.id])

        let reopened = Workspace(libraryRoot: root.appendingPathComponent("Library"), preferences: preferences)
        reopened.scope = "album:\(album.id)"
        reopened.sort = .captured
        XCTAssertEqual(reopened.photos.map(\.captureDate), ["2024:03:31 00:00:00", hidden.captureDate, "2024:03:31 00:01:00"])
        reopened.undoEdit()
        XCTAssertEqual(reopened.photos.map(\.id), [hidden.id])
        XCTAssertEqual(reopened.library.photos.first(where: { $0.id == first.id }), first)
        XCTAssertEqual(reopened.library.photos.first(where: { $0.id == next.id }), next)
        XCTAssertEqual(reopened.library.photos.first(where: { $0.id == sibling.id }), sibling)
        reopened.redoEdit()
        XCTAssertEqual(reopened.photos.map(\.id), [first.id, hidden.id, next.id])
        XCTAssertFalse(reopened.applyCaptureDateCorrection(preview, for: request))
        XCTAssertEqual(reopened.history.undo.count, 1)
        XCTAssertEqual(try reopened.repository?.load().photos, reopened.library.photos)
    }

    func testEmptiedTrashPrunesOnlyItsDatesFromGroupedHistory() throws {
        let first = photo("First", "2024:02:28 20:00:00")
        let next = photo("Next", "2024:02:28 20:00:12")
        let request = CaptureDateCorrection(photos: [first, next], preferredReferenceID: first.id)
        var library = Library()
        library.photos = [first, next]
        let adjusted = try request.preview("2024:02:29 20:00:00", preservingIntervals: true)
        let previous = try XCTUnwrap(library.replaceCaptureDates(adjusted.changes))
        var history = EditHistory()
        history.record(.captureDates(previous))

        library.photos.removeFirst()
        history.discardEmptiedTrash(photoIDs: [first.id], originalIDs: [first.originalID])
        XCTAssertNotNil(history.step(in: &library, redoing: false))
        XCTAssertEqual(library.photos, [next])
        XCTAssertNotNil(history.step(in: &library, redoing: true))
        XCTAssertEqual(library.photos.map(\.captureDate), ["2024:02:29 20:00:12"])
    }

    @MainActor
    func testCorrectionExportsNewEXIFAndPreservesManagedAndReferencedBytes() throws {
        let (root, preferences) = try fixture()
        defer { cleanUp(root, preferences) }
        let repo = try LibraryRepository.createEmpty(at: root.appendingPathComponent("Library"))
        let oldDate = "2023:05:06 07:08:09"
        let newDate = "2024:02:29 15:20:25"
        let managed = root.appendingPathComponent("Managed.jpg")
        let reference = root.appendingPathComponent("Referenced.jpg")
        try writeJPEG(to: managed, captureDate: oldDate, red: 0.15)
        try writeJPEG(to: reference, captureDate: nil, red: 0.7)
        var draft = try repo.load()
        XCTAssertTrue(try repo.importPhoto(managed, projectID: nil, into: &draft))
        var importOptions = ImportOptions()
        importOptions.storage = .referenced
        XCTAssertTrue(try repo.importPhoto(reference, projectID: nil, into: &draft, options: importOptions))
        let originalURLs = try draft.photos.map(repo.originalURL)
        let originalHashes = try originalURLs.map(LibraryRepository.digest)

        let workspace = Workspace(libraryRoot: repo.root, preferences: preferences)
        workspace.batchMode = true
        workspace.batchSelection = Set(workspace.photos.map(\.id))
        workspace.openCaptureDateCorrection()
        let request = try XCTUnwrap(workspace.captureDateCorrection)
        XCTAssertTrue(workspace.applyCaptureDateCorrection(
            try request.preview(newDate, preservingIntervals: false), for: request))
        for (index, photo) in workspace.library.photos.enumerated() {
            for format in [ExportFormat.jpeg, .png, .tiff, .heif] {
                for includeEXIF in [true, false] {
                    var options = ExportOptions()
                    options.format = format
                    options.exif = includeEXIF
                    let output = root.appendingPathComponent("\(index)-\(includeEXIF).\(format.suffix)")
                    try Renderer.export(photo, repository: repo, to: output, options: options)
                    XCTAssertEqual(try embeddedDate(output), includeEXIF ? newDate : nil)
                }
            }
            var options = ExportOptions()
            options.format = .original
            options.exif = true
            let output = root.appendingPathComponent("original-\(index).jpg")
            try Renderer.export(photo, repository: repo, to: output, options: options)
            XCTAssertEqual(try LibraryRepository.digest(output), originalHashes[index])
        }
        XCTAssertEqual(try originalURLs.map(LibraryRepository.digest), originalHashes)
        XCTAssertEqual(try embeddedDate(originalURLs[0]), oldDate)
        XCTAssertNil(try embeddedDate(reference))
        XCTAssertEqual(workspace.library.version, 2)
        preferences.set(true, forKey: "history.persist")
        workspace.undoEdit()
        XCTAssertEqual(workspace.library.photos.map(\.captureDate), [oldDate, ""])
        XCTAssertEqual(workspace.library.version, 8)
        let backup = root.appendingPathComponent("Backup")
        try LibraryBackup.create(from: repo, to: backup)
        let restored = root.appendingPathComponent("Restored")
        try LibraryBackup.restore(from: backup, to: restored, excluding: repo.root)
        let reopened = Workspace(libraryRoot: restored, preferences: preferences)
        reopened.redoEdit()
        XCTAssertEqual(reopened.library.photos.map(\.captureDate), [newDate, newDate])
    }

    private func photo(_ name: String, _ value: String) -> Photo {
        Photo(filename: name + ".jpg", originalName: name, projectID: nil, width: 20, height: 16,
              camera: "", captureDate: value, sha256: name)
    }

    private func fixture() throws -> (URL, UserDefaults) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueDates-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let preferences = try XCTUnwrap(UserDefaults(suiteName: root.lastPathComponent))
        return (root, preferences)
    }

    private func cleanUp(_ root: URL, _ preferences: UserDefaults) {
        preferences.removePersistentDomain(forName: root.lastPathComponent)
        try? FileManager.default.removeItem(at: root)
    }

    private func writeJPEG(to url: URL, captureDate: String?, red: CGFloat) throws {
        let context = try XCTUnwrap(CGContext(data: nil, width: 20, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(),
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(red: red, green: 0.5, blue: 0.3, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 20, height: 16))
        let image = try XCTUnwrap(context.makeImage())
        let writer = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        let properties = captureDate.map { [kCGImagePropertyExifDictionary: [kCGImagePropertyExifDateTimeOriginal: $0]] }
        CGImageDestinationAddImage(writer, image, properties as CFDictionary?)
        XCTAssertTrue(CGImageDestinationFinalize(writer))
    }

    private func embeddedDate(_ url: URL) throws -> String? {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)) as NSDictionary
        return (properties[kCGImagePropertyExifDictionary] as? NSDictionary)?[kCGImagePropertyExifDateTimeOriginal] as? String
    }
}
