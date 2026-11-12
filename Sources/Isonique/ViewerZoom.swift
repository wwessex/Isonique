import CoreGraphics
import SwiftUI

/// Pure zoom policy used by the Viewer button and native magnification gesture.
/// A nil scale means Fit; non-nil values are image-pixel scale factors.
enum ViewerZoom {
    static let minimumScale: CGFloat = 0.01
    static let maximumScale: CGFloat = 8
    static let fitHysteresis: CGFloat = 1.005

    static func toggled(_ scale: CGFloat?) -> CGFloat? {
        scale == nil ? 1 : nil
    }

    static func magnified(from base: CGFloat?, by magnification: CGFloat,
                          fitScale: CGFloat? = nil) -> CGFloat? {
        guard magnification.isFinite, magnification > 0 else { return base }
        let boundedFit = fitScale.flatMap { value in
            value.isFinite && value > 0 ? min(maximumScale, max(minimumScale, value)) : nil
        }
        let startingScale = base ?? boundedFit ?? 1
        let proposed = startingScale * magnification
        if let boundedFit, proposed <= boundedFit * fitHysteresis { return nil }
        if base == nil, boundedFit == nil, magnification < fitHysteresis { return nil }
        return min(maximumScale, max(minimumScale, proposed))
    }

    static func percentage(_ scale: CGFloat) -> String {
        "\(Int((scale * 100).rounded()))%"
    }

    static func fittedScale(viewportSize: CGSize, imageSize: CGSize,
                            padding: CGFloat = 32) -> CGFloat {
        guard viewportSize.width.isFinite, viewportSize.height.isFinite,
              imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let width = max(1, viewportSize.width - padding)
        let height = max(1, viewportSize.height - padding)
        return min(maximumScale, max(minimumScale,
            min(width / imageSize.width, height / imageSize.height)))
    }
}

struct ViewerViewportSizePreference: PreferenceKey {
    static var defaultValue = CGSize.zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) { value = nextValue() }
}
