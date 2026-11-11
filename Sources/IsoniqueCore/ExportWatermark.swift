import CoreGraphics
import CoreText
import Foundation

public enum ExportWatermark {
    public static func apply(_ settings: WatermarkSettings?, to image: CGImage) throws -> CGImage {
        guard let settings else { return image }
        let text = String(settings.text.replacingOccurrences(of: "\n", with: " ").prefix(200))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return image }
        try Task.checkCancellation()

        let opacity = settings.opacity.isFinite ? min(1, max(0.1, settings.opacity)) : 0.75
        let scale = settings.scale.isFinite ? min(0.2, max(0.02, settings.scale)) : 0.06
        guard let colourSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: colourSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue |
                                          CGBitmapInfo.byteOrder32Big.rawValue) else {
            throw LibraryError.unsupportedImage("watermark")
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))

        var fontSize = max(8, CGFloat(min(image.width, image.height)) * scale)
        var line = makeLine(text, fontSize: fontSize, opacity: opacity)
        let initialWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let initialMargin = max(4, fontSize * 0.6)
        let availableWidth = max(1, CGFloat(image.width) - initialMargin * 2)
        if initialWidth > availableWidth {
            fontSize *= availableWidth / initialWidth
            line = makeLine(text, fontSize: fontSize, opacity: opacity)
        }

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
        let margin = max(4, fontSize * 0.6)
        let canvasWidth = CGFloat(image.width)
        let canvasHeight = CGFloat(image.height)
        let baseline: CGPoint
        switch settings.position {
        case .topLeft:
            baseline = CGPoint(x: margin, y: canvasHeight - margin - ascent)
        case .topRight:
            baseline = CGPoint(x: canvasWidth - margin - lineWidth, y: canvasHeight - margin - ascent)
        case .center:
            baseline = CGPoint(x: (canvasWidth - lineWidth) / 2,
                               y: (canvasHeight - ascent - descent) / 2 + descent)
        case .bottomLeft:
            baseline = CGPoint(x: margin, y: margin + descent)
        case .bottomRight:
            baseline = CGPoint(x: canvasWidth - margin - lineWidth, y: margin + descent)
        }

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -max(1, fontSize * 0.06)),
                          blur: max(1, fontSize * 0.12),
                          color: CGColor(gray: 0, alpha: min(1, opacity + 0.15)))
        context.textPosition = baseline
        CTLineDraw(line, context)
        context.restoreGState()
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("watermark") }
        return result
    }

    private static func makeLine(_ text: String, fontSize: CGFloat, opacity: Double) -> CTLine {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica-Bold" as CFString, fontSize, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String):
                CGColor(gray: 1, alpha: opacity)
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    }
}
