import CoreGraphics
import Foundation
import IsoniqueCore

struct WhiteBalanceSamplingRequest: Equatable {
    let id = UUID()
    let photoID: UUID
    let adjustments: Adjustments
    let originalRevision: Int
}

struct WhiteBalanceSampleWork: Equatable {
    let request: WhiteBalanceSamplingRequest
    let point: CGPoint

    func load(from url: URL) async throws -> WhiteBalanceSample? {
        try Task.checkCancellation()
        let sample = Task.detached(priority: .userInitiated) {
            try Renderer.sampleWhiteBalance(url, adjustments: request.adjustments, viewerPoint: point)
        }
        let result = await withTaskCancellationHandler {
            await sample.result
        } onCancel: { sample.cancel() }
        try Task.checkCancellation()
        return try result.get()
    }
}

extension Workspace {
    var activeWhiteBalanceSampling: WhiteBalanceSamplingRequest? {
        guard let whiteBalanceSampling, loupeActive, !compareOriginal, !busy, !batchMode, !isViewingTrash,
              originalStatusRevision == whiteBalanceSampling.originalRevision,
              let photo = selected, photo.id == whiteBalanceSampling.photoID,
              photo.adjustments == whiteBalanceSampling.adjustments else { return nil }
        return whiteBalanceSampling
    }

    func startWhiteBalanceSampling(photoID: UUID) {
        guard !busy, canShowLoupe, let photo = selected, photo.id == photoID else { return }
        curveSampling = nil
        targetedColorSampling = nil
        stopComparison()
        chooseTool(.select)
        showLoupe = true
        whiteBalanceSampling = WhiteBalanceSamplingRequest(photoID: photo.id, adjustments: photo.adjustments,
                                                           originalRevision: originalStatusRevision)
    }

    func finishWhiteBalanceSampling(_ request: WhiteBalanceSamplingRequest, sample: WhiteBalanceSample?) {
        guard activeWhiteBalanceSampling == request else { return }
        guard let sample else {
            status = "White Balance · choose an opaque, unclipped neutral pixel"
            return
        }
        var recipe = request.adjustments
        recipe.warmth = 0
        recipe.temperatureKelvin = (sample.kelvin / 10).rounded() * 10
        recipe.tint = sample.tint
        whiteBalanceSampling = nil
        compareOriginal = false
        guard recipe != request.adjustments else {
            status = "White Balance · sample is already neutral"
            return
        }
        edit { $0.adjustments = recipe }
        status = "White Balance · \(Int(recipe.temperatureKelvin)) K · tint \(recipe.tint.formatted(.number.precision(.fractionLength(2))))"
    }
}
