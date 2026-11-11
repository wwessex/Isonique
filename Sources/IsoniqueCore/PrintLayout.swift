import Foundation
import CoreGraphics
import CoreText

public enum PrintLayoutStyle: String, Codable, CaseIterable, Identifiable {
    case contactSheet = "Contact Sheet"
    case proof = "Single-Photo Proof"
    public var id: Self { self }
}

public enum PrintPageSize: String, Codable, CaseIterable, Identifiable {
    case a4 = "A4"
    case a3 = "A3"
    case letter = "US Letter"

    public var id: Self { self }
    public var portraitDimensions: CGSize {
        switch self {
        case .a4: return CGSize(width: 595.28, height: 841.89)
        case .a3: return CGSize(width: 841.89, height: 1190.55)
        case .letter: return CGSize(width: 612, height: 792)
        }
    }
}

public enum PrintOrientation: String, Codable, CaseIterable, Identifiable {
    case portrait = "Portrait"
    case landscape = "Landscape"
    public var id: Self { self }
}

public enum PrintCaptionStyle: String, Codable, CaseIterable, Identifiable {
    case none = "None"
    case versionName = "Version Name"
    case filename = "Original Filename"
    case caption = "Caption"
    case nameAndCaption = "Name and Caption"
    public var id: Self { self }
}

public enum PrintColourMode: String, Codable, CaseIterable, Identifiable {
    case sRGB = "sRGB Colour"
    case displayP3 = "Display P3 Colour"
    case monochrome = "Black and White"
    public var id: Self { self }
}

public struct PrintLayoutOptions: Codable, Equatable {
    public var style: PrintLayoutStyle
    public var pageSize: PrintPageSize
    public var orientation: PrintOrientation
    public var marginPoints: Double
    public var columns: Int
    public var rows: Int
    public var caption: PrintCaptionStyle
    public var colourMode: PrintColourMode

    public init(style: PrintLayoutStyle = .contactSheet, pageSize: PrintPageSize = .a4,
                orientation: PrintOrientation = .portrait, marginPoints: Double = 36,
                columns: Int = 3, rows: Int = 4, caption: PrintCaptionStyle = .versionName,
                colourMode: PrintColourMode = .sRGB) {
        self.style = style
        self.pageSize = pageSize
        self.orientation = orientation
        self.marginPoints = marginPoints
        self.columns = columns
        self.rows = rows
        self.caption = caption
        self.colourMode = colourMode
    }

    public var pageDimensions: CGSize {
        let portrait = pageSize.portraitDimensions
        return orientation == .portrait ? portrait : CGSize(width: portrait.height, height: portrait.width)
    }
}

public struct PrintPreset: Codable, Equatable, Identifiable {
    public var id: UUID
    public var name: String
    public var options: PrintLayoutOptions
    public init(id: UUID = UUID(), name: String, options: PrintLayoutOptions) {
        self.id = id
        self.name = name
        self.options = options
    }
}

public enum PrintLayoutError: LocalizedError, Equatable {
    case noPhotos
    case invalidMargins
    case invalidGrid
    case outputFailed

    public var errorDescription: String? {
        switch self {
        case .noPhotos: return "Choose at least one photo to print."
        case .invalidMargins: return "Margins must leave printable space on the selected page."
        case .invalidGrid: return "Contact sheets support between 1 and 10 rows and columns."
        case .outputFailed: return "Isonique could not create the print document."
        }
    }
}

public struct PrintLayoutCell: Identifiable, Equatable {
    public let id: UUID
    public let photo: Photo
    public let frame: CGRect
    public let imageFrame: CGRect
    public let captionFrame: CGRect
    public let caption: String
}

public struct PrintLayoutPage: Identifiable, Equatable {
    public let id: Int
    public let cells: [PrintLayoutCell]
}

public struct PrintLayoutPlan: Equatable {
    public let options: PrintLayoutOptions
    public let pageSize: CGSize
    public let pages: [PrintLayoutPage]
}

public enum PrintLayout {
    private static let gap: CGFloat = 12

    public static func plan(photos: [Photo], options: PrintLayoutOptions) throws -> PrintLayoutPlan {
        guard !photos.isEmpty else { throw PrintLayoutError.noPhotos }
        let pageSize = options.pageDimensions
        let margin = CGFloat(options.marginPoints)
        guard options.marginPoints.isFinite, margin >= 0,
              margin * 2 < pageSize.width, margin * 2 < pageSize.height else {
            throw PrintLayoutError.invalidMargins
        }
        let columns = options.style == .proof ? 1 : options.columns
        let rows = options.style == .proof ? 1 : options.rows
        guard (1...10).contains(columns), (1...10).contains(rows) else {
            throw PrintLayoutError.invalidGrid
        }
        let content = CGRect(x: margin, y: margin,
                             width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let cellWidth = (content.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
        let cellHeight = (content.height - gap * CGFloat(rows - 1)) / CGFloat(rows)
        guard cellWidth > 8, cellHeight > 8 else { throw PrintLayoutError.invalidMargins }
        let perPage = columns * rows
        var pages: [PrintLayoutPage] = []
        for pageIndex in 0..<Int(ceil(Double(photos.count) / Double(perPage))) {
            let start = pageIndex * perPage
            let end = min(photos.count, start + perPage)
            let cells = photos[start..<end].enumerated().map { offset, photo in
                let row = offset / columns
                let column = offset % columns
                let x = content.minX + CGFloat(column) * (cellWidth + gap)
                let y = content.maxY - CGFloat(row + 1) * cellHeight - CGFloat(row) * gap
                let frame = CGRect(x: x, y: y, width: cellWidth, height: cellHeight)
                let text = caption(for: photo, style: options.caption)
                let captionHeight = text.isEmpty ? 0 : min(options.style == .proof ? 54 : 38, cellHeight * 0.24)
                let inset = options.style == .proof ? min(12, cellWidth * 0.02) : 4
                let captionFrame = CGRect(x: frame.minX + inset, y: frame.minY + inset,
                                          width: max(0, frame.width - inset * 2), height: captionHeight)
                let imageFrame = CGRect(x: frame.minX + inset,
                                        y: frame.minY + captionHeight + (captionHeight > 0 ? inset : 0),
                                        width: max(0, frame.width - inset * 2),
                                        height: max(0, frame.height - captionHeight - inset * 2))
                return PrintLayoutCell(id: photo.id, photo: photo, frame: frame,
                                       imageFrame: imageFrame, captionFrame: captionFrame, caption: text)
            }
            pages.append(PrintLayoutPage(id: pageIndex, cells: cells))
        }
        return PrintLayoutPlan(options: options, pageSize: pageSize, pages: pages)
    }

    public static func pdfData(photos: [Photo], repository: LibraryRepository,
                               options: PrintLayoutOptions) throws -> Data {
        let plan = try plan(photos: photos, options: options)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw PrintLayoutError.outputFailed
        }
        var mediaBox = CGRect(origin: .zero, size: plan.pageSize)
        let metadata: [CFString: Any] = [
            kCGPDFContextCreator: "Isonique",
            kCGPDFContextTitle: options.style.rawValue
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                      metadata as CFDictionary) else {
            throw PrintLayoutError.outputFailed
        }
        for page in plan.pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            for cell in page.cells {
                let original = try repository.availableOriginalURL(cell.photo)
                let rendered = try Renderer.render(original, adjustments: cell.photo.adjustments)
                let image = try converted(rendered, mode: options.colourMode)
                context.saveGState()
                context.interpolationQuality = .high
                context.draw(image, in: aspectFit(CGSize(width: image.width, height: image.height), inside: cell.imageFrame))
                context.restoreGState()
                if !cell.caption.isEmpty { drawCaption(cell.caption, in: cell.captionFrame, context: context) }
            }
            context.endPDFPage()
        }
        context.closePDF()
        guard data.length > 0 else { throw PrintLayoutError.outputFailed }
        return data as Data
    }

    public static func writePDF(photos: [Photo], repository: LibraryRepository,
                                options: PrintLayoutOptions, to destination: URL) throws {
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        let files = FileManager.default
        guard target.pathExtension.lowercased() == "pdf",
              !target.path.hasPrefix(repository.root.path + "/"),
              !files.fileExists(atPath: target.path),
              (try? files.destinationOfSymbolicLink(atPath: target.path)) == nil,
              !target.pathComponents.contains(where: {
                  ["aplibrary", "aperturelibrary", "photoslibrary", "photolibrary", "app"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
              }) else { throw LibraryError.unsafePath }
        try pdfData(photos: photos, repository: repository, options: options)
            .write(to: target, options: .withoutOverwriting)
    }

    public static func caption(for photo: Photo, style: PrintCaptionStyle) -> String {
        switch style {
        case .none: return ""
        case .versionName: return photo.displayName
        case .filename: return photo.sourceName ?? photo.originalName
        case .caption: return photo.caption
        case .nameAndCaption:
            return photo.caption.isEmpty ? photo.displayName : "\(photo.displayName)\n\(photo.caption)"
        }
    }

    private static func aspectFit(_ image: CGSize, inside bounds: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return bounds }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    private static func converted(_ image: CGImage, mode: PrintColourMode) throws -> CGImage {
        let colourSpace: CGColorSpace
        let bitmapInfo: UInt32
        switch mode {
        case .sRGB:
            guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw PrintLayoutError.outputFailed }
            colourSpace = space
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        case .displayP3:
            guard let space = CGColorSpace(name: CGColorSpace.displayP3) else { throw PrintLayoutError.outputFailed }
            colourSpace = space
            bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        case .monochrome:
            colourSpace = CGColorSpaceCreateDeviceGray()
            bitmapInfo = CGImageAlphaInfo.none.rawValue
        }
        guard let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colourSpace,
                                      bitmapInfo: bitmapInfo) else { throw PrintLayoutError.outputFailed }
        context.setRenderingIntent(.relativeColorimetric)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let converted = context.makeImage() else { throw PrintLayoutError.outputFailed }
        return converted
    }

    private static func drawCaption(_ text: String, in rect: CGRect, context: CGContext) {
        guard rect.width > 0, rect.height > 0 else { return }
        let fontSize = min(12, max(7, rect.height * 0.32))
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
            kCTForegroundColorAttributeName: CGColor(gray: 0.08, alpha: 1)
        ]
        let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)!
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: rect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(), path, nil)
        CTFrameDraw(frame, context)
    }
}
