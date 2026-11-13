import CoreGraphics
import Foundation
import Vision

/// Unit coordinates from the top left of the EXIF-oriented original.
public struct FaceRegion: Codable, Equatable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init?(imageRect: CGRect) {
        guard !imageRect.isInfinite, !imageRect.isNull, imageRect.size.width > 0, imageRect.size.height > 0,
              [imageRect.minX, imageRect.minY, imageRect.width, imageRect.height].allSatisfy(\.isFinite) else { return nil }
        let clipped = imageRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return nil }
        x = clipped.minX
        y = clipped.minY
        width = clipped.width
        height = clipped.height
    }

    init?(visionRect: CGRect) {
        guard !visionRect.isInfinite, !visionRect.isNull else { return nil }
        self.init(imageRect: CGRect(x: visionRect.minX, y: 1 - visionRect.maxY,
                                    width: visionRect.width, height: visionRect.height))
    }

    public var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }

    var isValid: Bool {
        [x, y, width, height].allSatisfy(\.isFinite) && x >= 0 && y >= 0
            && width > 0 && height > 0 && x + width <= 1.000001 && y + height <= 1.000001
    }

    func overlapsFace(_ other: FaceRegion) -> Bool {
        let overlap = rect.intersection(other.rect)
        guard !overlap.isNull else { return false }
        let intersection = overlap.width * overlap.height
        return intersection / (width * height + other.width * other.height - intersection) >= 0.4
    }
}

public struct PhotoFace: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var region: FaceRegion
    public private(set) var name: String?

    public init(region: FaceRegion) {
        id = UUID()
        self.region = region
    }

    public static func cleanedName(_ value: String) -> String {
        String(value.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(160))
            .trimmingCharacters(in: .whitespaces)
    }

    public static func personKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public mutating func assignName(_ value: String) {
        let cleaned = Self.cleanedName(value)
        name = cleaned.isEmpty ? nil : cleaned
    }
}

public struct PhotoPeople: Codable, Equatable, Sendable {
    public var faces: [PhotoFace] = []
    public private(set) var scanned = false
    private var dismissedRegions: [FaceRegion] = []

    public init() {}

    public var hasData: Bool { scanned || !faces.isEmpty || !dismissedRegions.isEmpty }

    public mutating func incorporateDetections(_ regions: [FaceRegion]) {
        scanned = true
        for region in regions where region.isValid {
            guard !dismissedRegions.contains(where: { $0.overlapsFace(region) }),
                  !faces.contains(where: { $0.region.overlapsFace(region) }) else { continue }
            faces.append(PhotoFace(region: region))
        }
    }

    public mutating func removeFace(_ id: UUID) {
        guard let index = faces.firstIndex(where: { $0.id == id }) else { return }
        rememberDismissal(faces.remove(at: index).region)
    }

    public mutating func moveFace(_ id: UUID, to region: FaceRegion) {
        guard let index = faces.firstIndex(where: { $0.id == id }), faces[index].region != region else { return }
        let previous = faces[index].region
        faces[index].region = region
        if !previous.overlapsFace(region) { rememberDismissal(previous) }
    }

    private mutating func rememberDismissal(_ region: FaceRegion) {
        if !dismissedRegions.contains(where: { $0.overlapsFace(region) }) { dismissedRegions.append(region) }
    }

    func validate() throws {
        guard Set(faces.map(\.id)).count == faces.count,
              faces.allSatisfy({ face in
                  face.region.isValid && (face.name.map { !$0.isEmpty && $0 == PhotoFace.cleanedName($0) } ?? true)
              }),
              dismissedRegions.allSatisfy(\.isValid) else {
            throw LibraryError.integrity("invalid People records")
        }
    }
}

public struct PhotoPeopleChange: Codable, Equatable {
    public let photoID: UUID
    public let people: PhotoPeople?

    public init(photoID: UUID, people: PhotoPeople?) {
        self.photoID = photoID
        self.people = people
    }
}

public extension Photo {
    var personNames: [String] { people?.faces.compactMap(\.name) ?? [] }
}

public extension Library {
    internal var hasPeopleData: Bool {
        photos.contains { $0.people != nil } ||
            albums.contains { $0.rule?.query?.criteria.contains { $0.field == .person } == true }
    }

    mutating func upgradeForPeople() {
        if version < 37, hasPeopleData { version = 37 }
    }

    mutating func replacePeople(_ changes: [PhotoPeopleChange]) -> [PhotoPeopleChange]? {
        applyPhotoFieldChanges(changes, photoID: \.photoID) { photo, change in
            let previous = PhotoPeopleChange(photoID: photo.id, people: photo.people)
            photo.people = change.people
            return previous
        }
    }
}

public enum FaceDetection {
    /// Preview and detection use the same orientation-corrected source space.
    public static func sourcePreview(at url: URL) throws -> CGImage {
        guard url.isFileURL else { throw LibraryError.unsafePath }
        return try Renderer.thumbnail(url, adjustments: Adjustments(), maxDimension: 2048)
    }

    public static func regions(in image: CGImage) async throws -> [FaceRegion] {
        try Task.checkCancellation()
        let faces = try await DetectFaceRectanglesRequest().perform(on: image, orientation: .up)
        try Task.checkCancellation()
        return faces.compactMap { observation in
            FaceRegion(visionRect: observation.boundingBox.cgRect)
        }.sorted { left, right in
            left.y == right.y ? left.x < right.x : left.y < right.y
        }
    }
}

public extension LibraryRepository {
    func verifiedFaceSource(for photo: Photo) throws -> CGImage {
        try Task.checkCancellation()
        let url = try availableOriginalURL(photo)
        try Self.verifyOriginal(url, photo: photo)
        try Task.checkCancellation()
        return try FaceDetection.sourcePreview(at: url)
    }
}
