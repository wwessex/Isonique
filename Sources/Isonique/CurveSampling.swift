import CoreGraphics
import Foundation
import IsoniqueCore

enum AutoCurvesMode { case combined, separate }

struct CurveSamplingRequest: Equatable {
    let id = UUID()
    let photoID: UUID
    let adjustments: Adjustments
    let originalRevision: Int
    let channel: CurveChannel
}

struct CurvePointSelection: Equatable {
    let id: UUID
    let photoID: UUID
    let channel: CurveChannel
    let input: Int
}

struct CurveSampleWork: Equatable {
    let request: CurveSamplingRequest
    let point: CGPoint

    func load(from url: URL) async throws -> Int? {
        try Task.checkCancellation()
        let sample = Task.detached(priority: .userInitiated) {
            try Renderer.sampleCurveInput(url, adjustments: request.adjustments, channel: request.channel,
                                          viewerPoint: point)
        }
        let result = await withTaskCancellationHandler {
            await sample.result
        } onCancel: { sample.cancel() }
        try Task.checkCancellation()
        return try result.get()
    }
}

extension Workspace {
    func applyAutoCurves(_ mode: AutoCurvesMode, input: ToneHistogram, for photo: Photo) {
        guard !busy, !batchMode, !isViewingTrash, let selected,
              selected.id == photo.id, selected.adjustments == photo.adjustments else { return }
        let channels: [(CurveChannel, [Int])] = mode == .combined
            ? [(.luminance, input.luminance)]
            : [(.red, input.red), (.green, input.green), (.blue, input.blue)]
        var recipe = photo.adjustments
        var foundRange = false
        for (channel, bins) in channels {
            guard let curve = ChannelCurve.automatic(from: bins) else { continue }
            foundRange = true
            recipe.setCurve(curve, for: channel)
        }
        guard foundRange else { status = "Auto Curves · insufficient tonal range"; return }
        guard recipe != photo.adjustments else { status = "Auto Curves · already applied"; return }
        compareOriginal = false
        edit { $0.adjustments = recipe }
    }

    var activeCurveSampling: CurveSamplingRequest? {
        guard let curveSampling, loupeActive, !compareOriginal, !busy, !batchMode, !isViewingTrash,
              originalStatusRevision == curveSampling.originalRevision,
              let photo = selected, photo.id == curveSampling.photoID,
              photo.adjustments == curveSampling.adjustments else { return nil }
        return curveSampling
    }

    func startCurveSampling(_ channel: CurveChannel, photoID: UUID) {
        guard !busy, canShowLoupe, let photo = selected, photo.id == photoID else { return }
        whiteBalanceSampling = nil
        targetedColorSampling = nil
        stopComparison()
        chooseTool(.select)
        showLoupe = true
        curveSampling = CurveSamplingRequest(photoID: photo.id, adjustments: photo.adjustments,
                                             originalRevision: originalStatusRevision, channel: channel)
    }

    func finishCurveSampling(_ request: CurveSamplingRequest, input: Int?) {
        guard activeCurveSampling == request else { return }
        guard let input else { status = "Curve sample · choose a visible pixel"; return }
        var curve = request.adjustments.curve(for: request.channel)
        guard curve.anchor(input: input) != nil else {
            status = "Curve sample · the channel has reached its point limit"
            return
        }
        curveSampling = nil
        setChannelCurve(curve, for: request.channel, photoID: request.photoID)
        if selected?.adjustments.curve(for: request.channel) == curve {
            curvePointSelection = CurvePointSelection(id: request.id, photoID: request.photoID,
                                                       channel: request.channel, input: input)
        }
    }
}
