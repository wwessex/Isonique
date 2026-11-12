import CoreGraphics
import Foundation

public struct LightTableItem: Codable, Equatable, Identifiable {
    public var id: UUID
    public var photoID: UUID
    public var centerX: Double
    public var centerY: Double
    public var width: Double
    public var height: Double
    public var rotation: Double
    public var zIndex: Int

    public init(id: UUID = UUID(), photoID: UUID, centerX: Double, centerY: Double,
                width: Double, height: Double, rotation: Double = 0, zIndex: Int = 0) {
        self.id = id
        self.photoID = photoID
        self.centerX = centerX
        self.centerY = centerY
        self.width = width
        self.height = height
        self.rotation = rotation
        self.zIndex = zIndex
    }
}

public enum LightTableAlignment: String, Codable, CaseIterable, Identifiable {
    case left = "Align Left"
    case horizontalCenter = "Align Horizontal Centres"
    case right = "Align Right"
    case top = "Align Top"
    case verticalCenter = "Align Vertical Centres"
    case bottom = "Align Bottom"
    public var id: Self { self }
}

public struct LightTableLayout: Codable, Equatable, Identifiable {
    public static let defaultCanvasSize = CGSize(width: 1600, height: 1000)
    public var id: UUID
    public var name: String
    public var canvasWidth: Double
    public var canvasHeight: Double
    public var items: [LightTableItem]

    public init(id: UUID = UUID(), name: String, canvasWidth: Double = 1600,
                canvasHeight: Double = 1000, items: [LightTableItem] = []) {
        self.id = id
        self.name = name
        self.canvasWidth = canvasWidth
        self.canvasHeight = canvasHeight
        self.items = items
    }

    public init(id: UUID = UUID(), name: String, photos: [Photo],
                canvasSize: CGSize = Self.defaultCanvasSize) {
        self.init(id: id, name: name, canvasWidth: canvasSize.width,
                  canvasHeight: canvasSize.height)
        add(photos)
    }

    public mutating func add(_ photos: [Photo]) {
        let existing = Set(items.map(\.photoID))
        let additions = photos.filter { !existing.contains($0.id) }
        guard !additions.isEmpty else { return }
        let newItems = additions.enumerated().map { offset, photo in
            LightTableItem(photoID: photo.id, centerX: canvasWidth / 2, centerY: canvasHeight / 2,
                           width: 320, height: 240, zIndex: items.count + offset)
        }
        let arrangedAdditions = arranged(newItems,
            photos: Dictionary(uniqueKeysWithValues: additions.map { ($0.id, $0) }))
        let baseIndex = items.count
        items.append(contentsOf: arrangedAdditions.enumerated().map { offset, value in
            var item = value
            item.zIndex = baseIndex + offset
            return item
        })
    }

    public mutating func move(_ itemID: UUID, to point: CGPoint) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].centerX = min(canvasWidth, max(0, point.x))
        items[index].centerY = min(canvasHeight, max(0, point.y))
    }

    public mutating func resize(_ itemID: UUID, to size: CGSize) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[index].width = min(canvasWidth, max(48, size.width))
        items[index].height = min(canvasHeight, max(48, size.height))
        move(itemID, to: CGPoint(x: items[index].centerX, y: items[index].centerY))
    }

    public mutating func rotate(_ itemIDs: Set<UUID>, by degrees: Double) {
        guard degrees.isFinite else { return }
        for index in items.indices where itemIDs.contains(items[index].id) {
            var angle = (items[index].rotation + degrees).truncatingRemainder(dividingBy: 360)
            if angle > 180 { angle -= 360 }
            if angle <= -180 { angle += 360 }
            items[index].rotation = angle
        }
    }

    public mutating func align(_ itemIDs: Set<UUID>, to alignment: LightTableAlignment) {
        let indices = items.indices.filter { itemIDs.contains(items[$0].id) }
        guard indices.count > 1 else { return }
        let left = indices.map { items[$0].centerX - items[$0].width / 2 }.min() ?? 0
        let right = indices.map { items[$0].centerX + items[$0].width / 2 }.max() ?? canvasWidth
        let top = indices.map { items[$0].centerY - items[$0].height / 2 }.min() ?? 0
        let bottom = indices.map { items[$0].centerY + items[$0].height / 2 }.max() ?? canvasHeight
        for index in indices {
            switch alignment {
            case .left: items[index].centerX = left + items[index].width / 2
            case .horizontalCenter: items[index].centerX = (left + right) / 2
            case .right: items[index].centerX = right - items[index].width / 2
            case .top: items[index].centerY = top + items[index].height / 2
            case .verticalCenter: items[index].centerY = (top + bottom) / 2
            case .bottom: items[index].centerY = bottom - items[index].height / 2
            }
        }
    }

    public mutating func bringToFront(_ itemIDs: Set<UUID>) {
        reorder(itemIDs, front: true)
    }

    public mutating func sendToBack(_ itemIDs: Set<UUID>) {
        reorder(itemIDs, front: false)
    }

    public mutating func remove(_ itemIDs: Set<UUID>) {
        items.removeAll { itemIDs.contains($0.id) }
        normalizeOrder()
    }

    public func validated(photoIDs: Set<UUID>? = nil) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              canvasWidth.isFinite, canvasHeight.isFinite,
              canvasWidth >= 100, canvasHeight >= 100 else { throw LightTableError.invalidLayout }
        var itemIDs: Set<UUID> = []
        for item in items {
            guard itemIDs.insert(item.id).inserted,
                  photoIDs?.contains(item.photoID) != false,
                  item.centerX.isFinite, item.centerY.isFinite,
                  item.width.isFinite, item.height.isFinite, item.rotation.isFinite,
                  item.width >= 48, item.height >= 48 else { throw LightTableError.invalidLayout }
        }
    }

    private mutating func reorder(_ itemIDs: Set<UUID>, front: Bool) {
        guard !itemIDs.isEmpty else { return }
        let selected = items.filter { itemIDs.contains($0.id) }.sorted { $0.zIndex < $1.zIndex }
        let others = items.filter { !itemIDs.contains($0.id) }.sorted { $0.zIndex < $1.zIndex }
        items = front ? others + selected : selected + others
        normalizeOrder()
    }

    private mutating func normalizeOrder() {
        for index in items.indices { items[index].zIndex = index }
    }

    private func arranged(_ source: [LightTableItem], photos: [UUID: Photo]) -> [LightTableItem] {
        guard !source.isEmpty else { return [] }
        let columns = max(1, Int(ceil(sqrt(Double(source.count) * canvasWidth / canvasHeight))))
        let rows = Int(ceil(Double(source.count) / Double(columns)))
        let gap = 36.0, margin = 60.0
        let cellWidth = max(80, (canvasWidth - margin * 2 - gap * Double(columns - 1)) / Double(columns))
        let cellHeight = max(80, (canvasHeight - margin * 2 - gap * Double(rows - 1)) / Double(rows))
        return source.enumerated().map { offset, value in
            var item = value
            let photo = photos[item.photoID]
            let aspect = photo.map { max(0.05, Double($0.width) / max(1, Double($0.height))) }
                ?? max(0.05, item.width / max(1, item.height))
            var width = min(420, cellWidth)
            var height = width / aspect
            if height > min(320, cellHeight) {
                height = min(320, cellHeight)
                width = height * aspect
            }
            item.width = max(48, width)
            item.height = max(48, height)
            let column = offset % columns, row = offset / columns
            item.centerX = margin + Double(column) * (cellWidth + gap) + cellWidth / 2
            item.centerY = margin + Double(row) * (cellHeight + gap) + cellHeight / 2
            item.zIndex = offset
            return item
        }
    }
}

public enum LightTableError: LocalizedError, Equatable {
    case noPhotos
    case invalidLayout
    case outputFailed

    public var errorDescription: String? {
        switch self {
        case .noPhotos: return "Choose at least one available photo for the Light Table."
        case .invalidLayout: return "The Light Table layout contains invalid geometry."
        case .outputFailed: return "Isonique could not create the Light Table document."
        }
    }
}

public enum LightTableOutput {
    public static func pdfData(layout: LightTableLayout, photos: [Photo],
                               repository: LibraryRepository) throws -> Data {
        try layout.validated()
        let byID = Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0) })
        let available = layout.items.sorted { $0.zIndex < $1.zIndex }.compactMap { item in
            byID[item.photoID].map { (item, $0) }
        }
        guard !available.isEmpty else { throw LightTableError.noPhotos }
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw LightTableError.outputFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: layout.canvasWidth, height: layout.canvasHeight)
        let metadata: [CFString: Any] = [
            kCGPDFContextCreator: "Isonique",
            kCGPDFContextTitle: layout.name
        ]
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox,
                                      metadata as CFDictionary) else { throw LightTableError.outputFailed }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(gray: 0.08, alpha: 1))
        context.fill(mediaBox)
        for (item, photo) in available {
            let original = try repository.availableOriginalURL(photo)
            let image = try Renderer.render(original, adjustments: photo.adjustments)
            context.saveGState()
            context.translateBy(x: item.centerX, y: layout.canvasHeight - item.centerY)
            context.rotate(by: CGFloat(-item.rotation * .pi / 180))
            let bounds = CGRect(x: -item.width / 2, y: -item.height / 2,
                                width: item.width, height: item.height)
            context.setFillColor(CGColor(gray: 0.03, alpha: 1))
            context.fill(bounds)
            context.interpolationQuality = .high
            context.draw(image, in: aspectFit(CGSize(width: image.width, height: image.height), inside: bounds))
            context.restoreGState()
        }
        context.endPDFPage()
        context.closePDF()
        guard data.length > 0 else { throw LightTableError.outputFailed }
        return data as Data
    }

    public static func writePDF(layout: LightTableLayout, photos: [Photo],
                                repository: LibraryRepository, to destination: URL) throws {
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        let files = FileManager.default
        guard target.pathExtension.lowercased() == "pdf",
              !target.path.hasPrefix(repository.root.path + "/"),
              !files.fileExists(atPath: target.path),
              (try? files.destinationOfSymbolicLink(atPath: target.path)) == nil,
              !target.pathComponents.contains(where: {
                  ["aplibrary", "aperturelibrary", "photoslibrary", "photolibrary", "app"]
                      .contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
              }) else {
            throw LibraryError.unsafePath
        }
        try pdfData(layout: layout, photos: photos, repository: repository)
            .write(to: target, options: .withoutOverwriting)
    }

    private static func aspectFit(_ image: CGSize, inside bounds: CGRect) -> CGRect {
        guard image.width > 0, image.height > 0 else { return bounds }
        let scale = min(bounds.width / image.width, bounds.height / image.height)
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}
