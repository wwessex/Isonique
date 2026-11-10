import CoreGraphics
import CryptoKit
import ImageIO
import XCTest
import IsoniqueCore

final class RawWorkflowTests: XCTestCase {
    func testCameraRAWImportTonePreviewAndExport() throws {
        let path = try XCTUnwrapOrSkip(ProcessInfo.processInfo.environment["ISONIQUE_RAW_FIXTURES"])
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let samples = [
            CaptureSample(file: "Sony-a7III.ARW", seconds: 1.0 / 50, aperture: 4, iso: 400, focalLength: 32, hasLens: true),
            CaptureSample(file: "Canon-EOS-R.CR3", seconds: 0.3, aperture: 11, iso: 100, focalLength: 85, hasLens: true),
            CaptureSample(file: "Nikon-Z6.NEF", seconds: 1, aperture: 6.7, iso: 100, focalLength: 52, hasLens: true),
            CaptureSample(file: "Ricoh-GR-III.DNG", seconds: 1.0 / 400, aperture: 5, iso: 100, focalLength: 18.3, hasLens: false)
        ]
        for sample in samples {
            do {
                try autoreleasepool { try check(directory.appendingPathComponent(sample.file), sample: sample) }
            } catch {
                XCTFail("\(sample.file): \(error.localizedDescription)")
            }
        }
    }

    private struct CaptureSample {
        let file: String
        let seconds: Double
        let aperture: Double
        let iso: Int
        let focalLength: Double
        let hasLens: Bool
    }

    private func check(_ source: URL, sample: CaptureSample) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("IsoniqueRAW-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: folder) }
        let repository = try LibraryRepository.createEmpty(at: folder.appendingPathComponent("Library"))
        let digest = try LibraryRepository.digest(source)
        var library = try repository.load()
        XCTAssertTrue(try repository.importPhoto(source, projectID: nil, into: &library), source.lastPathComponent)
        var photo = try XCTUnwrap(library.photos.first)
        XCTAssertFalse(photo.camera.isEmpty, source.lastPathComponent)
        photo.adjustments.darkLevelQuarter = 0.30
        var curve = ChannelCurve.identity
        curve.insertPoint(input: 128, output: 150)
        photo.adjustments.setCurve(curve, for: .luminance)
        library.photos[0] = photo
        library.upgradeForQuarterTones()
        try repository.save(library)
        let saved = try XCTUnwrap(repository.load().photos.first)
        XCTAssertEqual(saved.adjustments, photo.adjustments)
        let exif = try repository.cameraEXIF(for: saved)
        XCTAssertEqual(saved.cameraEXIF, exif, sample.file)
        XCTAssertEqual(try XCTUnwrap(exif.exposureSeconds), sample.seconds, accuracy: 0.000001, sample.file)
        XCTAssertEqual(try XCTUnwrap(exif.fNumber), sample.aperture, accuracy: 0.001, sample.file)
        XCTAssertEqual(exif.iso, sample.iso, sample.file)
        XCTAssertEqual(try XCTUnwrap(exif.focalLengthMM), sample.focalLength, accuracy: 0.001, sample.file)
        if sample.hasLens { XCTAssertFalse(try XCTUnwrap(exif.lens).isEmpty, sample.file) }
        let original = try repository.availableOriginalURL(saved)
        let previewStart = DispatchTime.now()
        let thumbnail = try Renderer.render(original, adjustments: saved.adjustments, maxDimension: 384)
        let previewMS = milliseconds(since: previewStart)
        XCTAssertEqual(max(thumbnail.width, thumbnail.height), 384)
        let neutral = try Renderer.render(original, adjustments: Adjustments(), maxDimension: 384)
        XCTAssertNotEqual(try pixelDigest(thumbnail), try pixelDigest(neutral))
        let input = try Renderer.adjustmentHistograms(original, adjustments: saved.adjustments)
        XCTAssertEqual(input.channelCurves.red.reduce(0, +), thumbnail.width * thumbnail.height)

        let fullStart = DispatchTime.now()
        let full = try Renderer.render(original, adjustments: saved.adjustments)
        let fullMS = milliseconds(since: fullStart)
        XCTAssertGreaterThanOrEqual(max(full.width, full.height), 4_000, source.lastPathComponent)
        var options = ExportOptions()
        options.format = .png
        let png = folder.appendingPathComponent("Edited.png")
        try Renderer.export(saved, repository: repository, to: png, options: options)
        let imageSource = try XCTUnwrap(CGImageSourceCreateWithURL(png as CFURL, nil))
        let exported = try XCTUnwrap(CGImageSourceCreateImageAtIndex(imageSource, 0, nil))
        XCTAssertEqual(exported.width, full.width)
        XCTAssertEqual(exported.height, full.height)
        XCTAssertEqual(try pixelDigest(full), try pixelDigest(exported))
        options.format = .original
        let originalExport = folder.appendingPathComponent("Original." + source.pathExtension)
        try Renderer.export(saved, repository: repository, to: originalExport, options: options)
        XCTAssertEqual(try LibraryRepository.digest(originalExport), digest)
        XCTAssertEqual(try LibraryRepository.digest(original), digest)
        XCTAssertEqual(try LibraryRepository.digest(source), digest)
        print("RAW \(source.lastPathComponent) \(full.width)×\(full.height), 384px \(previewMS) ms, full \(fullMS) ms")
    }

    private func milliseconds(since start: DispatchTime) -> UInt64 {
        (DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    private func pixelDigest(_ image: CGImage) throws -> SHA256.Digest {
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let bytesPerRow = image.width * 4
        let info = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try XCTUnwrap(CGContext(data: nil, width: image.width, height: image.height,
                                             bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                             space: space, bitmapInfo: info))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let data = Data(bytesNoCopy: try XCTUnwrap(context.data), count: bytesPerRow * image.height, deallocator: .none)
        return withExtendedLifetime(context) { SHA256.hash(data: data) }
    }

    private func XCTUnwrapOrSkip(_ path: String?) throws -> String {
        guard let path, !path.isEmpty else { throw XCTSkip("Set ISONIQUE_RAW_FIXTURES to run with external camera files") }
        return path
    }
}
