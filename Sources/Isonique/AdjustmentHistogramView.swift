import SwiftUI
import IsoniqueCore

struct AdjustmentHistogramRequest: Equatable {
    let photoID: UUID
    let url: URL
    let originalRevision: Int
    let settings: Adjustments

    init(photo: Photo, url: URL, originalRevision: Int) {
        photoID = photo.id
        self.url = url
        self.originalRevision = originalRevision
        var input = photo.adjustments
        // The input distributions are measured before geometry and the final luminance curve.
        input.quarterTurns = 0
        input.flipHorizontal = false
        input.flipVertical = false
        input.straighten = 0
        input.crop = nil
        input.lensDistortion = 0
        input.setCurve(.identity, for: .luminance)
        settings = input
    }

    func load() async throws -> AdjustmentHistograms {
        try Task.checkCancellation()
        let render = Task.detached(priority: .userInitiated) {
            try Renderer.adjustmentHistograms(url, adjustments: settings)
        }
        let result = await withTaskCancellationHandler {
            await render.result
        } onCancel: { render.cancel() }
        try Task.checkCancellation()
        return try result.get()
    }
}

struct AdjustmentHistogramView: View {
    let series: [([Int], Color)]

    var body: some View {
        Canvas { context, size in
            let maximum = Double(series.compactMap { $0.0.max() }.max() ?? 0)
            guard maximum > 0 else { return }
            for (bins, tint) in series {
                let width = size.width / CGFloat(bins.count)
                var bars = Path()
                for (index, count) in bins.enumerated() where count > 0 {
                    let height = size.height * Double(count) / maximum
                    bars.addRect(CGRect(x: CGFloat(index) * width, y: size.height - height,
                                        width: width, height: height))
                }
                context.fill(bars, with: .color(tint.opacity(0.38)))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

extension ToneHistogram {
    var rgbSeries: [([Int], Color)] { [(red, .red), (green, .green), (blue, .blue)] }
}
