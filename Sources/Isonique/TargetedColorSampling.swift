import CoreGraphics
import Foundation
import IsoniqueCore

struct TargetedColorSamplingRequest: Equatable {
    let id = UUID()
    let photoID: UUID
    let adjustments: Adjustments
    let originalRevision: Int
}

struct TargetedColorSampleWork: Equatable {
    let request: TargetedColorSamplingRequest
    let point: CGPoint

    func load(from url: URL) async throws -> TargetedColorSample? {
        try Task.checkCancellation()
        let sample = Task.detached(priority: .userInitiated) {
            try Renderer.sampleTargetedColor(url, adjustments: request.adjustments, viewerPoint: point)
        }
        let result = await withTaskCancellationHandler {
            await sample.result
        } onCancel: { sample.cancel() }
        try Task.checkCancellation()
        return try result.get()
    }
}

extension Workspace {
    var activeTargetedColorSampling: TargetedColorSamplingRequest? {
        guard let targetedColorSampling, loupeActive, !compareOriginal, !busy, !batchMode, !isViewingTrash,
              originalStatusRevision == targetedColorSampling.originalRevision,
              let photo = selected, photo.id == targetedColorSampling.photoID,
              photo.adjustments == targetedColorSampling.adjustments else { return nil }
        return targetedColorSampling
    }

    func startTargetedColorSampling(photoID: UUID) {
        guard !busy, canShowLoupe, let photo = selected, photo.id == photoID else { return }
        curveSampling = nil
        whiteBalanceSampling = nil
        stopComparison()
        chooseTool(.select)
        showLoupe = true
        targetedColorSampling = TargetedColorSamplingRequest(photoID: photo.id, adjustments: photo.adjustments,
                                                             originalRevision: originalStatusRevision)
    }

    func finishTargetedColorSampling(_ request: TargetedColorSamplingRequest, sample: TargetedColorSample?) {
        guard activeTargetedColorSampling == request else { return }
        guard let sample else {
            status = String(localized: "Targeted Color · choose an opaque pixel with visible color")
            return
        }
        let existing = Set(request.adjustments.targetedColors.map(\.name))
        var number = request.adjustments.targetedColors.count + 1
        while existing.contains("Sampled \(number)") { number += 1 }
        let target = TargetedColorAdjustment(name: "Sampled \(number)",
                                             centerHue: (sample.hue * 10).rounded() / 10)
        targetedColorSampling = nil
        compareOriginal = false
        edit { $0.adjustments.targetedColors.append(target) }
        if selected?.adjustments.targetedColors.contains(where: { $0.id == target.id }) == true {
            targetedColorSelection = target.id
            status = String(localized: "Targeted Color") + " · " +
                String(localized: "sampled \(Int(target.centerHue.rounded()))° hue")
        }
    }
}
