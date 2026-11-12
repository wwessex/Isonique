import CoreGraphics

/// Pure zoom policy used by the Viewer button and native magnification gesture.
/// A nil scale means Fit; non-nil values are image-pixel scale factors.
enum ViewerZoom {
    static let minimumScale: CGFloat = 0.25
    static let maximumScale: CGFloat = 8
    static let enterThreshold: CGFloat = 1.03
    static let exitThreshold: CGFloat = 0.20

    static func toggled(_ scale: CGFloat?) -> CGFloat? {
        scale == nil ? 1 : nil
    }

    static func magnified(from base: CGFloat?, by magnification: CGFloat) -> CGFloat? {
        guard magnification.isFinite, magnification > 0 else { return base }
        guard let base else {
            guard magnification >= enterThreshold else { return nil }
            return min(maximumScale, max(1, magnification))
        }
        let proposed = base * magnification
        guard proposed >= exitThreshold else { return nil }
        return min(maximumScale, max(minimumScale, proposed))
    }

    static func percentage(_ scale: CGFloat) -> String {
        "\(Int((scale * 100).rounded()))%"
    }
}
