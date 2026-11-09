import IsoniqueCore
import XCTest
@testable import Isonique

final class AdjustmentHistogramTests: XCTestCase {
    func testRequestTracksPhotoAndUpstreamRecipe() {
        let url = URL(fileURLWithPath: "/tmp/input-histogram.png")
        var photo = Photo(filename: "test.png", originalName: "test.png", projectID: nil,
                          width: 8, height: 8, camera: "", captureDate: "", sha256: "fixture")
        let baseline = AdjustmentHistogramRequest(photo: photo, url: url, originalRevision: 0)
        photo.adjustments.flipHorizontal = true
        var curve = ChannelCurve.identity
        curve.insertPoint(input: 128, output: 190)
        photo.adjustments.setCurve(curve, for: .luminance)
        XCTAssertEqual(AdjustmentHistogramRequest(photo: photo, url: url, originalRevision: 0), baseline)
        photo.adjustments.setCurve(curve, for: .green)
        XCTAssertNotEqual(AdjustmentHistogramRequest(photo: photo, url: url, originalRevision: 0), baseline)
        photo.adjustments.setCurve(.identity, for: .green)
        XCTAssertNotEqual(AdjustmentHistogramRequest(photo: photo, url: url, originalRevision: 1), baseline)
        photo.id = UUID()
        XCTAssertNotEqual(AdjustmentHistogramRequest(photo: photo, url: url, originalRevision: 0), baseline)
    }

    func testCancelledRequestStopsBeforeOpeningOriginal() async throws {
        let photo = Photo(filename: "missing.png", originalName: "missing.png", projectID: nil,
                          width: 8, height: 8, camera: "", captureDate: "", sha256: "fixture")
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)/missing.png")
        let request = AdjustmentHistogramRequest(photo: photo, url: url, originalRevision: 0)
        let worker = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await request.load()
        }
        do {
            _ = try await worker.value
            XCTFail("Cancelled analysis returned a histogram")
        } catch is CancellationError {}
    }
}
