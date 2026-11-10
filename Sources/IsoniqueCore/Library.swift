import Foundation
import Darwin
import ImageIO
import CoreGraphics
import CryptoKit
import UniformTypeIdentifiers

/// Ratings shared by the catalogue, review controls and metadata import.
public enum RatingRules {
    public static let rejected = -1
    public static let unrated = 0
    public static let maximum = 5
    public static let invalid = -100 // Internal sentinel, never a user rating.
    public static func clamp(_ value: Int) -> Int { min(maximum, max(rejected, value)) }
    /// Add the requested delta and clamp it to the user rating range.
    public static func adjusting(_ current: Int, by delta: Int) -> Int {
        let (sum, overflow) = current.addingReportingOverflow(delta)
        return overflow ? (delta > 0 ? maximum : rejected) : clamp(sum)
    }
    public static func rejectionRating(isRejected: Bool) -> Int { isRejected ? rejected : unrated }
    public static func stars(_ value: Int) -> String { String(repeating: "★", count: max(unrated, clamp(value))) }
}

/// Raw values are persisted in Isonique Smart Album rules.
public enum RatingFilter: Int, CaseIterable, Identifiable {
    case all = 6, unratedAndAbove = 0, oneAndAbove = 1, twoAndAbove = 2
    case threeAndAbove = 3, fourAndAbove = 4, five = 5, unrated = 7, rejected = 8
    public var id: Int { rawValue }
    public var label: String {
        switch self {
        case .all: return "All ratings"
        case .unratedAndAbove: return "Unrated and above"
        case .oneAndAbove: return "★ and above"
        case .twoAndAbove: return "★★ and above"
        case .threeAndAbove: return "★★★ and above"
        case .fourAndAbove: return "★★★★ and above"
        case .five: return "★★★★★"
        case .unrated: return "Unrated only"
        case .rejected: return "Rejected only"
        }
    }
    public func includes(_ rating: Int) -> Bool {
        switch self {
        case .all: return true
        case .unrated: return rating == RatingRules.unrated
        case .rejected: return rating == RatingRules.rejected
        case .five: return rating == RatingRules.maximum
        case .unratedAndAbove: return rating >= RatingRules.unrated
        default: return rating >= rawValue
        }
    }
}

/// Combine the rating and flag filters without changing either filter's behavior.
public enum BrowserFilterRules {
    public static func includes(rating: Int, flagged: Bool, ratingFilter: RatingFilter, flaggedOnly: Bool) -> Bool {
        ratingFilter.includes(rating) && (!flaggedOnly || flagged)
    }
}

/// Crop coordinates are fractions of the oriented and straightened image, from its top left.
public struct PhotoCrop: Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}
/// Straightening bounds shared by the editor and stored recipes.
public enum StraightenRules {
    public static let minimum = -45.0
    public static let maximum = 45.0
    public static let range = minimum...maximum
    public static func clamp(_ degrees: Double) -> Double {
        degrees.isFinite ? min(maximum, max(minimum, degrees)) : 0
    }
    /// Add each gesture delta, then clamp the result to the supported range.
    public static func applying(rotation delta: Double, to current: Double) -> Double {
        guard delta.isFinite else { return clamp(current) }
        return clamp(current + delta)
    }
}
public struct Adjustments: Codable, Equatable {
    public var exposure: Double = 0
    public var brightness: Double = 0
    public var vibrancy: Double = 0
    public var sepia: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var warmth: Double = 0
    public var tint: Double = 0
    public var shadows: Double = 0
    public var highlights: Double = 0
    public var quarterTurns: Int = 0
    public var flipHorizontal = false
    public var flipVertical = false
    public var straighten: Double = 0
    public var crop: PhotoCrop?
    public var blackPoint: Double = 0
    public var whitePoint: Double = 1
    public var gamma: Double = 1
    public var curveShadows: Double = 0.25
    public var curveMidtones: Double = 0.5
    public var curveHighlights: Double = 0.75
    public internal(set) var channelCurves: ChannelCurves?
    public internal(set) var channelLevels: ChannelLevels?
    public internal(set) var levelQuarterTones: LevelQuarterTones?
    public var lensDistortion: Double = 0
    public var localBrushes: [LocalBrushStroke] = []
    public init() {}
    enum CodingKeys: String, CodingKey { case exposure, brightness, vibrancy, sepia, contrast, saturation, warmth, tint, shadows, highlights, quarterTurns, flipHorizontal, flipVertical, straighten, crop, lensDistortion, blackPoint, whitePoint, gamma, curveShadows, curveMidtones, curveHighlights, channelCurves, channelLevels, levelQuarterTones, localBrushes }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        exposure = try values.decodeIfPresent(Double.self, forKey: .exposure) ?? 0
        brightness = try values.decodeIfPresent(Double.self, forKey: .brightness) ?? 0
        vibrancy = try values.decodeIfPresent(Double.self, forKey: .vibrancy) ?? 0
        sepia = try values.decodeIfPresent(Double.self, forKey: .sepia) ?? 0
        contrast = try values.decodeIfPresent(Double.self, forKey: .contrast) ?? 1
        saturation = try values.decodeIfPresent(Double.self, forKey: .saturation) ?? 1
        warmth = try values.decodeIfPresent(Double.self, forKey: .warmth) ?? 0
        tint = try values.decodeIfPresent(Double.self, forKey: .tint) ?? 0
        shadows = try values.decodeIfPresent(Double.self, forKey: .shadows) ?? 0
        highlights = try values.decodeIfPresent(Double.self, forKey: .highlights) ?? 0
        quarterTurns = try values.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0
        flipHorizontal = try values.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        flipVertical = try values.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        // Apply the same bounds when restoring a stored recipe.
        straighten = StraightenRules.clamp(try values.decodeIfPresent(Double.self, forKey: .straighten) ?? 0)
        crop = try values.decodeIfPresent(PhotoCrop.self, forKey: .crop)
        blackPoint = try values.decodeIfPresent(Double.self, forKey: .blackPoint) ?? 0
        whitePoint = try values.decodeIfPresent(Double.self, forKey: .whitePoint) ?? 1
        gamma = try values.decodeIfPresent(Double.self, forKey: .gamma) ?? 1
        curveShadows = try values.decodeIfPresent(Double.self, forKey: .curveShadows) ?? 0.25
        curveMidtones = try values.decodeIfPresent(Double.self, forKey: .curveMidtones) ?? 0.5
        curveHighlights = try values.decodeIfPresent(Double.self, forKey: .curveHighlights) ?? 0.75
        channelCurves = try values.decodeIfPresent(ChannelCurves.self, forKey: .channelCurves)
        channelLevels = try values.decodeIfPresent(ChannelLevels.self, forKey: .channelLevels)
        levelQuarterTones = try values.decodeIfPresent(LevelQuarterTones.self, forKey: .levelQuarterTones)
        lensDistortion = try values.decodeIfPresent(Double.self, forKey: .lensDistortion) ?? 0
        localBrushes = try values.decodeIfPresent([LocalBrushStroke].self, forKey: .localBrushes) ?? []
    }
}
/// Independent editing groups; selective stamping preserves every unselected group.
public enum AdjustmentGroup: String, CaseIterable, Codable, Identifiable {
    case basic = "Exposure & color", whiteBalance = "White balance", tone = "Highlights & shadows", geometry = "Crop, rotation & lens"
    case localBrush = "Local brush masks"
    public var id: String { rawValue }
}
public enum FlipAxis: String, CaseIterable, Identifiable {
    case horizontal = "Flip Horizontally"
    case vertical = "Flip Vertically"
    public var id: Self { self }
}

public extension Adjustments {
    mutating func toggleFlip(_ axis: FlipAxis) {
        switch axis {
        case .horizontal:
            flipHorizontal.toggle()
            if var crop {
                crop.x = max(0, 1 - crop.x - crop.width)
                self.crop = crop
            }
        case .vertical:
            flipVertical.toggle()
            if var crop {
                crop.y = max(0, 1 - crop.y - crop.height)
                self.crop = crop
            }
        }
    }

    func stamping(onto target: Adjustments, groups: Set<AdjustmentGroup>) -> Adjustments {
        var result = target
        if groups.contains(.basic) {
            result.exposure = exposure; result.contrast = contrast; result.saturation = saturation
            result.brightness = brightness; result.vibrancy = vibrancy; result.sepia = sepia
        }
        if groups.contains(.whiteBalance) { result.warmth = warmth; result.tint = tint }
        if groups.contains(.tone) {
            result.shadows = shadows; result.highlights = highlights
            result.blackPoint = blackPoint; result.whitePoint = whitePoint; result.gamma = gamma
            result.curveShadows = curveShadows; result.curveMidtones = curveMidtones; result.curveHighlights = curveHighlights
            result.channelCurves = channelCurves
            result.channelLevels = channelLevels
            result.levelQuarterTones = levelQuarterTones
        }
        if groups.contains(.geometry) {
            result.quarterTurns = quarterTurns; result.straighten = straighten
            result.crop = crop; result.lensDistortion = lensDistortion
            result.flipHorizontal = flipHorizontal; result.flipVertical = flipVertical
        }
        if groups.contains(.localBrush) { result.localBrushes = localBrushes }
        return result
    }
}
public enum AdjustmentPreset: String, CaseIterable, Identifiable {
    case natural = "Natural", vivid = "Vivid", monochrome = "Black & White", warm = "Warm", sepia = "Sepia"
    public var id: String { rawValue }
    public func applying(to current: Adjustments) -> Adjustments {
        var recipe = Adjustments()
        switch self {
        case .natural: break
        case .vivid: recipe.contrast = 1.12; recipe.saturation = 1.25
        case .monochrome: recipe.saturation = 0; recipe.contrast = 1.1
        case .warm: recipe.warmth = 0.3; recipe.saturation = 1.05
        case .sepia: recipe.sepia = 1
        }
        return recipe.stamping(onto: current, groups: [.basic, .whiteBalance, .tone])
    }
}
public struct Collection: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var rule: SmartAlbumRule?
    public internal(set) var gpxTracks: [ProjectGPXTrack]?
    public init(name: String) { self.name = name }
}
public struct Photo: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var trashedAt: Date?
    public var sharedOriginalID: UUID?
    public var versionName: String?
    public var referencedPath: String?
    public var stackID: UUID?
    public var versions: [PhotoVersion]?
    public var pairID: UUID?
    public var sourceName: String?
    public var filename: String
    public var originalName: String
    public var importedAt = Date()
    public var projectID: UUID?
    public var albumIDs: Set<UUID> = []
    public var rating = 0
    public var flagged = false
    public var colorLabel: PhotoColorLabel?
    public var caption = ""
    public var iptc: IPTCMetadata?
    public var keywords = ""
    public var keywordPaths: [KeywordPath]?
    public var width: Int
    public var height: Int
    public var camera: String
    public var cameraEXIF: CameraEXIF?
    public var gpsIndex: GPSIndex?
    public var locationOverride: PhotoLocationOverride?
    public var captureDate: String
    public var sha256: String
    public var adjustments = Adjustments()
    public init(filename: String, originalName: String, projectID: UUID?, width: Int, height: Int, camera: String, captureDate: String, sha256: String) {
        self.filename = filename; self.originalName = originalName; self.projectID = projectID
        self.width = width; self.height = height; self.camera = camera; self.captureDate = captureDate; self.sha256 = sha256
    }
}
enum CatalogueRevision: Equatable {
    case missing
    case saved(SHA256.Digest)

    init(_ data: Data) { self = .saved(SHA256.hash(data: data)) }
}

public struct Library: Codable {
    // This is the revision the value was based on, never part of the on-disk schema.
    var catalogueRevision: CatalogueRevision?
    private enum CodingKeys: String, CodingKey {
        case projectExportMembership, pendingFinderTrash, history, stackBrowser, version, photos, projects, albums
    }

    var projectExportMembership: ProjectExportMembership?
    var pendingFinderTrash: [PendingFinderTrash]?
    public var history: EditHistory?
    public var stackBrowser: StackBrowserState?
    public var version = 1
    public var photos: [Photo] = []
    public var projects: [Collection] = []
    public var albums: [Collection] = []
    public init() {}

    public func hasSameCatalogueRevision(as other: Library) -> Bool {
        catalogueRevision != nil && catalogueRevision == other.catalogueRevision
    }

    private func hasRecipe(where includes: (Adjustments) -> Bool) -> Bool {
        func matches(_ photo: Photo) -> Bool {
            includes(photo.adjustments) || (photo.versions?.contains { includes($0.adjustments) } ?? false)
        }
        return photos.contains(where: matches) ||
            (history?.undo.contains { $0.photo.map(matches) ?? false } ?? false) ||
            (history?.redo.contains { $0.photo.map(matches) ?? false } ?? false)
    }

    public mutating func upgradeForBrushRecipes() {
        if version < 4, hasRecipe(where: { !$0.localBrushes.isEmpty }) { version = 4 }
    }

    public mutating func upgradeForChannelCurves() {
        if version < 5, hasRecipe(where: { $0.channelCurves?.isEmpty == false }) { version = 5 }
    }

    public mutating func upgradeForChannelLevels() {
        if version < 6, hasRecipe(where: { $0.channelLevels?.isEmpty == false }) { version = 6 }
    }

    public mutating func upgradeForQuarterTones() {
        if version < 7, hasRecipe(where: \.hasLevelQuarterTones) { version = 7 }
    }

    private var hasKeywordPaths: Bool {
        photos.contains { $0.keywordPaths?.isEmpty == false }
            || albums.contains { $0.rule?.query?.criteria.contains { $0.field == .keywordPath } == true }
    }

    fileprivate mutating func upgradeForKeywordPaths() {
        if version < 10, hasKeywordPaths { version = 10 }
    }

    fileprivate var hasIPTCMetadata: Bool {
        photos.contains { $0.iptc?.isEmpty == false }
    }

    fileprivate var hasIPTCRules: Bool {
        albums.contains { $0.rule?.query?.criteria.contains { $0.field.iptcField != nil } == true }
    }

    fileprivate var hasEXIFSearch: Bool {
        photos.contains { $0.cameraEXIF?.isEmpty == false }
            || albums.contains { $0.rule?.query?.criteria.contains { $0.field.isEXIF } == true }
    }

    fileprivate var hasGPSSearch: Bool {
        photos.contains { $0.gpsIndex?.coordinates != nil }
            || albums.contains { $0.rule?.query?.criteria.contains { $0.field.isGPS } == true }
    }

    fileprivate var hasLocationOverrides: Bool { photos.contains { $0.locationOverride != nil } }
    fileprivate var hasProjectGPXTracks: Bool { projects.contains { $0.gpxTracks?.isEmpty == false } }

    func validateSchema() throws {
        if version < 18, hasProjectGPXWaypoints { throw LibraryError.unsupportedVersion }
        if version < 17, hasProjectGPXTracks { throw LibraryError.unsupportedVersion }
        try validateProjectGPXTracks()
        if version < 16, hasLocationOverrides { throw LibraryError.unsupportedVersion }
        if version < 15, hasGPSSearch { throw LibraryError.unsupportedVersion }
        if version < 14, hasEXIFSearch { throw LibraryError.unsupportedVersion }
        if version < 12, hasIPTCRules { throw LibraryError.unsupportedVersion }
        if version < 11, hasIPTCMetadata { throw LibraryError.unsupportedVersion }
        if version < 10, hasKeywordPaths { throw LibraryError.unsupportedVersion }
        if let requiredVersion = history?.requiredCatalogueVersion, version < requiredVersion {
            throw LibraryError.unsupportedVersion
        }
        if (7...18).contains(version) { return }
        guard !hasRecipe(where: \.hasLevelQuarterTones) else { throw LibraryError.unsupportedVersion }
        if version == 6 { return }
        guard !hasRecipe(where: { $0.channelLevels?.isEmpty == false }) else { throw LibraryError.unsupportedVersion }
        if version == 5 { return }
        guard !hasRecipe(where: { $0.channelCurves?.isEmpty == false }) else { throw LibraryError.unsupportedVersion }
        if version == 4 { return }
        guard !hasRecipe(where: { !$0.localBrushes.isEmpty }) else { throw LibraryError.unsupportedVersion }
        if version == 3 { return }
        guard (1...2).contains(version), stackBrowser == nil,
              !photos.contains(where: { $0.sharedOriginalID != nil || $0.versionName != nil }) else {
            throw LibraryError.unsupportedVersion
        }
        if version == 1,
           photos.contains(where: { $0.referencedPath != nil }) ||
           albums.contains(where: { $0.rule?.query != nil || $0.rule?.projectID != nil }) {
            throw LibraryError.unsupportedVersion
        }
    }
}
public enum LibraryError: LocalizedError {
    case unsafePath, unsupportedImage(String), integrity(String), unsupportedVersion, invalidLibrary
    case originalUnavailable(String), staleCatalogue
    public var errorDescription: String? {
        switch self {
        case .unsafePath: return "This location is unsafe. Choose a separate Isonique library folder."
        case .unsupportedImage(let name): return "Cannot decode \(name) with this Mac's image support."
        case .integrity(let name): return "Integrity verification failed: \(name). The source was not modified."
        case .unsupportedVersion: return "This library was created by an unsupported newer version."
        case .invalidLibrary: return "The selected folder is not an Aperture library with a Masters or Originals folder."
        case .staleCatalogue: return "This library changed since it was loaded. Use File → Reload Library, then try your edit again."
        case .originalUnavailable(let name): return "Original unavailable: \(name). Reconnect its drive or relink the file."
        }
    }
}
public struct RecoveryResult {
    public var imported = 0
    public var duplicates = 0
    public var unsupported: [String] = []
    public var skipped: Int { duplicates + unsupported.count }
}
public final class LibraryRepository {
    public let root: URL
    private let fm = FileManager.default
    public static func createEmpty(at destination: URL) throws -> LibraryRepository {
        let target = destination.standardizedFileURL
        let parent = target.deletingLastPathComponent().resolvingSymlinksInPath()
        let root = parent.appendingPathComponent(target.lastPathComponent, isDirectory: true)
        let fm = FileManager.default
        try validateRoot(root)
        var ancestor = parent
        while ancestor.path != "/" {
            guard !fm.fileExists(atPath: ancestor.appendingPathComponent("catalog.json").path) else {
                throw LibraryError.unsafePath
            }
            ancestor.deleteLastPathComponent()
        }
        // Non-recursive creation rejects existing folders, symlinks and missing parents.
        try fm.createDirectory(at: root, withIntermediateDirectories: false)
        do {
            let repository = try LibraryRepository(root: root)
            _ = try repository.openOrCreateCatalogue()
            return repository
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }

    static func validateRoot(_ root: URL) throws {
        // Never create our catalogue inside a legacy library or application bundle.
        guard !root.pathComponents.contains(where: {
            ["aplibrary", "aperturelibrary", "photolibrary", "photoslibrary", "app"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased())
        }) else { throw LibraryError.unsafePath }
    }

    public init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try Self.validateRoot(self.root)
        if fm.fileExists(atPath: self.root.path), !fm.fileExists(atPath: self.root.appendingPathComponent("catalog.json").path) {
            let entries = try fm.contentsOfDirectory(atPath: self.root.path)
            guard entries.isEmpty else { throw LibraryError.unsafePath }
        }
        try fm.createDirectory(at: self.root.appendingPathComponent("Originals"), withIntermediateDirectories: true)
        guard self.root.appendingPathComponent("Originals").resolvingSymlinksInPath().path == self.root.appendingPathComponent("Originals").path else { throw LibraryError.unsafePath }
    }
    private var catalogueURL: URL { root.appendingPathComponent("catalog.json") }

    private func catalogueDataIfPresent() throws -> Data? {
        do {
            try LibraryBackup.regularFile(catalogueURL)
            return try Data(contentsOf: catalogueURL)
        } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    public func load() throws -> Library {
        guard let data = try catalogueDataIfPresent() else {
            var empty = Library()
            empty.catalogueRevision = .missing
            return empty
        }
        return try loadedLibrary(from: data)
    }

    /// Open an existing catalogue without touching its bytes, or initialize a new library once.
    public func openOrCreateCatalogue() throws -> Library {
        let loaded = try load()
        guard loaded.catalogueRevision == .missing else { return loaded }
        return try withCatalogueWriteLock {
            let current = try load()
            return current.catalogueRevision == .missing ? try writeCatalogue(current) : current
        }
    }

    public func reloadCatalogue() throws -> Library {
        guard let data = try catalogueDataIfPresent() else { throw LibraryError.integrity("catalogue file is missing") }
        return try loadedLibrary(from: data)
    }

    private func loadedLibrary(from data: Data) throws -> Library {
        var library = try LibraryBackup.decodeCatalogue(data)
        for index in library.photos.indices { library.photos[index].rating = RatingRules.clamp(library.photos[index].rating) }
        for photo in try library.uniqueOriginals() { _ = try originalURL(photo) }
        return library
    }

    /// Publish a catalogue and return the new base for subsequent edits.
    /// Detached catalogues constructed with Library() have no base to check.
    @discardableResult
    public func save(_ library: Library) throws -> Library {
        try withCatalogueWriteLock {
            try checkCatalogueRevision(of: library)
            return try writeCatalogue(library)
        }
    }

    // Call under the write lock when checking immediately before publication.
    func checkCatalogueRevision(of library: Library) throws {
        guard let expected = library.catalogueRevision else { return }
        let current = try catalogueDataIfPresent().map(CatalogueRevision.init) ?? .missing
        guard expected == current else { throw LibraryError.staleCatalogue }
    }

    func checkWorkspaceCatalogue(_ expected: Library?, matches current: Library) throws {
        guard let expected else { return }
        guard expected.hasSameCatalogueRevision(as: current) else { throw LibraryError.staleCatalogue }
    }

    func withCatalogueWriteLock<Result>(_ body: () throws -> Result) throws -> Result {
        let descriptor = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno
            if code == EWOULDBLOCK {
                throw LibraryError.integrity("another catalogue write is finishing; try again")
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
        return try body()
    }

    // The caller holds the catalogue write lock through this atomic replacement.
    func writeCatalogue(_ library: Library) throws -> Library {
        var normalized = library
        normalized.upgradeForKeywordPaths()
        if normalized.version < 18, normalized.hasProjectGPXWaypoints { normalized.version = 18 }
        if normalized.version < 17, normalized.hasProjectGPXTracks { normalized.version = 17 }
        if normalized.version < 16, normalized.hasLocationOverrides { normalized.version = 16 }
        if normalized.version < 15, normalized.hasGPSSearch { normalized.version = 15 }
        if normalized.version < 14, normalized.hasEXIFSearch { normalized.version = 14 }
        if normalized.version < 12, normalized.hasIPTCRules { normalized.version = 12 }
        if normalized.version < 11, normalized.hasIPTCMetadata { normalized.version = 11 }
        if let requiredVersion = normalized.history?.requiredCatalogueVersion {
            normalized.version = max(normalized.version, requiredVersion)
        }
        try normalized.validateSchema()
        _ = try normalized.uniqueOriginals()
        for index in normalized.photos.indices {
            normalized.photos[index].rating = RatingRules.clamp(normalized.photos[index].rating)
            normalized.photos[index].adjustments.straighten = StraightenRules.clamp(normalized.photos[index].adjustments.straighten)
        }
        let data = try JSONEncoder().encode(normalized)
        try data.write(to: catalogueURL, options: .atomic)
        normalized.catalogueRevision = CatalogueRevision(data)
        return normalized
    }
    public func originalURL(_ photo: Photo) throws -> URL {
        let managed = try managedOriginalURL(photo.filename)
        if let path = photo.referencedPath { return try Self.referenceURL(path, libraryRoot: root) }
        return managed
    }
    func managedOriginalURL(_ filename: String) throws -> URL {
        try Self.managedOriginalURL(filename, in: root)
    }

    static func managedOriginalURL(_ filename: String, in root: URL) throws -> URL {
        guard filename == (filename as NSString).lastPathComponent, !filename.isEmpty, filename != ".", filename != ".." else { throw LibraryError.unsafePath }
        let base = root.appendingPathComponent("Originals").resolvingSymlinksInPath()
        let url = base.appendingPathComponent(filename)
        guard base.path == root.appendingPathComponent("Originals").path,
              url.resolvingSymlinksInPath() == url,
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw LibraryError.unsafePath }
        return url
    }
    public static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty { hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public func importPhoto(_ source: URL, projectID: UUID?, into library: inout Library,
                            options: ImportOptions? = nil, albumID: UUID? = nil) throws -> Bool {
        let input = source.standardizedFileURL.resolvingSymlinksInPath()
        guard try input.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else {
            throw LibraryError.unsupportedImage(source.lastPathComponent)
        }
        let hash = try Self.digest(input)
        if library.photos.contains(where: { $0.sha256 == hash }) { return false }

        let sidecar = source.deletingPathExtension().appendingPathExtension("xmp")
        let metadata = options?.readSidecars == true && fm.fileExists(atPath: sidecar.path)
            ? try MetadataXML.read(sidecar) : []
        let suffix = input.pathExtension.lowercased()
        let filename = UUID().uuidString + (suffix.isEmpty ? "" : "." + suffix)
        let referenced = options?.storage == .referenced
        let imageURL: URL
        if referenced {
            imageURL = try Self.referenceURL(input.path, libraryRoot: root)
        } else {
            imageURL = try managedOriginalURL(filename)
        }
        var committed = false
        defer { if !referenced && !committed { try? fm.removeItem(at: imageURL) } }
        if !referenced {
            // Copy the resolved regular file, so a selected Finder symlink never becomes a managed link.
            try fm.copyItem(at: input, to: imageURL)
            guard try Self.digest(imageURL) == hash else { throw LibraryError.integrity(source.lastPathComponent) }
        }
        guard let imageSource = CGImageSourceCreateWithURL(imageURL as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            throw LibraryError.unsupportedImage(source.lastPathComponent)
        }
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let camera = [tiff[kCGImagePropertyTIFFMake as String] as? String, tiff[kCGImagePropertyTIFFModel as String] as? String].compactMap { $0 }.joined(separator: " ")
        var photo = Photo(filename: filename, originalName: source.lastPathComponent, projectID: projectID,
                          width: width, height: height, camera: camera,
                          captureDate: exif[kCGImagePropertyExifDateTimeOriginal as String] as? String ?? "", sha256: hash)
        let primaryProperties = CGImageSourceGetPrimaryImageIndex(imageSource) == 0 ? properties
            : try? Self.primaryImageProperties(in: imageSource, name: photo.originalName)
        if let primaryProperties {
            photo.cameraEXIF = CameraEXIF(properties: primaryProperties)
            photo.gpsIndex = GPSIndex(properties: primaryProperties)
        }
        let iptc = properties[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
        photo.caption = iptc[kCGImagePropertyIPTCCaptionAbstract as String] as? String ?? ""
        if let keywords = iptc[kCGImagePropertyIPTCKeywords as String] as? [String] {
            photo.keywords = keywords.joined(separator: ", ")
        }
        var rating = (iptc[kCGImagePropertyIPTCStarRating as String] as? NSNumber)?.intValue
        let embedded = CGImageSourceCopyMetadataAtIndex(imageSource, 0, nil)
        let iptcMetadata = IPTCMetadata(embedded: iptc, xmp: embedded)
        if !iptcMetadata.isEmpty { photo.iptc = iptcMetadata }
        if let embedded {
            if let paths = try? XMPMetadata.keywordPaths(from: embedded), !paths.isEmpty { photo.keywordPaths = paths }
            if let value = CGImageMetadataCopyStringValueWithPath(embedded, nil, "xmp:Rating" as CFString) as String?,
               let embeddedRating = Int(value) { rating = embeddedRating }
        }
        if let rating { photo.rating = RatingRules.clamp(rating) }
        if let options {
            photo.sourceName = source.lastPathComponent
            photo = options.applying(to: photo)
        }
        for record in metadata { photo = record.applying(to: photo) }
        if let albumID { photo.albumIDs.insert(albumID) }

        guard try Self.digest(input) == hash else { throw LibraryError.integrity(source.lastPathComponent) }
        if referenced { photo.referencedPath = imageURL.path }
        let oldVersion = library.version
        if referenced { library.version = max(library.version, 2) }
        library.photos.append(photo)
        do { library = try save(library) } catch {
            library.photos.removeLast()
            library.version = oldVersion
            throw error
        }
        committed = true
        return true
    }
    public func embeddedIPTC(for photo: Photo) -> IPTCMetadata {
        guard let url = try? availableOriginalURL(photo),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return IPTCMetadata() }
        return Self.embeddedIPTC(in: source)
    }

    static func embeddedIPTC(in source: CGImageSource) -> IPTCMetadata {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        let iptc = properties?[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
        return IPTCMetadata(embedded: iptc, xmp: CGImageSourceCopyMetadataAtIndex(source, 0, nil))
    }

    public static func imageFiles(in folder: URL, shouldContinue: () -> Bool = { true }) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard shouldContinue() else { break }
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            if values?.isRegularFile == true, ImportOptions.imageExtensions.contains(url.pathExtension.lowercased()) || CGImageSourceCreateWithURL(url as CFURL, nil) != nil { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
    /// Makes a verified, disposable copy before reading legacy originals. No proprietary database writes.
    public func recoverLegacy(_ source: URL, into library: inout Library) throws -> RecoveryResult {
        let resolved = source.resolvingSymlinksInPath()
        guard !root.path.hasPrefix(resolved.path + "/"), !resolved.path.hasPrefix(root.path + "/"), resolved != root else { throw LibraryError.unsafePath }
        guard ["Masters", "Originals"].contains(where: { fm.fileExists(atPath: resolved.appendingPathComponent($0).path) }) else { throw LibraryError.invalidLibrary }
        func manifest(_ base: URL) throws -> [String: String] {
            guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { throw LibraryError.invalidLibrary }
            var result: [String: String] = [:]
            for case let url as URL in enumerator {
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw LibraryError.unsafePath }
                if values.isRegularFile == true { result[url.pathComponents.suffix(enumerator.level).joined(separator: "/")] = try Self.digest(url) }
            }
            return result
        }
        let before = try manifest(resolved)
        let staging = root.appendingPathComponent("Recovery-" + UUID().uuidString)
        try fm.copyItem(at: resolved, to: staging)
        defer { try? fm.removeItem(at: staging) }
        let copied = try manifest(staging)
        guard copied == before, try manifest(resolved) == before else { throw LibraryError.integrity("legacy library copy") }
        let project = Collection(name: "Recovered · " + source.deletingPathExtension().lastPathComponent)
        var draft = library
        draft.projects.append(project)
        library = try save(draft)
        var result = RecoveryResult()
        for folder in ["Masters", "Originals"] {
            let files = Self.imageFiles(in: staging.appendingPathComponent(folder))
            for image in files {
                do {
                    if try importPhoto(image, projectID: project.id, into: &library) { result.imported += 1 }
                    else { result.duplicates += 1 }
                } catch LibraryError.unsupportedImage {
                    result.unsupported.append(image.resolvingSymlinksInPath().pathComponents.dropFirst(staging.resolvingSymlinksInPath().pathComponents.count).joined(separator: "/"))
                }
                // Disk, catalogue and integrity failures stop recovery; they are not
                // misleadingly reported as unsupported photographs.
            }
        }
        guard try manifest(resolved) == before else { throw LibraryError.integrity("legacy library changed during recovery") }
        return result
    }
}
public enum Renderer {
    public static func render(_ url: URL, adjustments: Adjustments, maxDimension: CGFloat? = nil) throws -> CGImage {
        // One documented, independent pixel pipeline for previews and exports.
        // ImageIO still provides file decoding, including system-supported camera RAW.
        return try renderOnCPU(url, adjustments: adjustments, maxDimension: maxDimension)
    }
    public static func thumbnail(_ url: URL, adjustments: Adjustments, maxDimension: Int) throws -> CGImage {
        let size = max(1, maxDimension)
        if adjustments != Adjustments() {
            return try render(url, adjustments: adjustments, maxDimension: CGFloat(size))
        }
        try Task.checkCancellation()
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw LibraryError.unsupportedImage(url.lastPathComponent)
        }
        return thumbnail
    }

    static func renderOnCPU(_ url: URL, adjustments: Adjustments, maxDimension: CGFloat?) throws -> CGImage {
        try renderWithGeometry(url, adjustments: adjustments, maxDimension: maxDimension).image
    }

    public static func renderWithGeometry(_ url: URL, adjustments: Adjustments,
                                          maxDimension: CGFloat? = nil) throws -> (image: CGImage, geometry: PhotoGeometry) {
        let (toned, geometry) = try renderToneInput(url, adjustments: adjustments, maxDimension: maxDimension)
        let toneTable = (0...255).map { TonalTools.map(Double($0) / 255, adjustments: adjustments) }
        let levels = try TonalTools.applying(toned, table: toneTable, curves: adjustments.channelCurves,
                                             channelLevels: adjustments.channelLevels)
        let image = try applyGeometry(applyLens(levels, amount: geometry.lensAmount), geometry: geometry)
        return (image, geometry)
    }

    public static func adjustmentHistograms(_ url: URL, adjustments: Adjustments) throws -> AdjustmentHistograms {
        let (toned, _) = try renderToneInput(url, adjustments: adjustments, maxDimension: 384)
        return try TonalTools.adjustmentHistograms(toned, adjustments: adjustments)
    }

    /// Sample the nearest oriented source pixel under a normalized point in the full-size Viewer.
    public static func sampleCurveInput(_ url: URL, adjustments: Adjustments, channel: CurveChannel,
                                        viewerPoint: CGPoint) throws -> Int? {
        guard (0...1).contains(viewerPoint.x), (0...1).contains(viewerPoint.y) else { return nil }
        let (toned, geometry) = try renderToneInput(url, adjustments: adjustments, maxDimension: nil)
        try Task.checkCancellation()
        let source = geometry.sourcePoint(x: viewerPoint.x, y: viewerPoint.y)
        let x = min(toned.width - 1, Int(source.x * Double(toned.width)))
        let y = min(toned.height - 1, Int(source.y * Double(toned.height)))
        return try TonalTools.curveInput(toned, pixel: CGRect(x: x, y: y, width: 1, height: 1),
                                         adjustments: adjustments, channel: channel)
    }

    private static func renderToneInput(_ url: URL, adjustments: Adjustments,
                                        maxDimension: CGFloat?) throws -> (CGImage, PhotoGeometry) {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] else { throw LibraryError.unsupportedImage(url.lastPathComponent) }
        let width = properties[kCGImagePropertyPixelWidth as String] as? Int ?? 1
        let height = properties[kCGImagePropertyPixelHeight as String] as? Int ?? 1
        let size = maxDimension.map { min(Int($0), max(width, height)) } ?? max(width, height)
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let (sourceWidth, sourceHeight) = (5...8).contains(orientation) ? (height, width) : (width, height)
        let mask = try LocalExposureMask(strokes: adjustments.localBrushes, sourceWidth: sourceWidth, sourceHeight: sourceHeight)
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size] as CFDictionary),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: decoded.width, height: decoded.height, bitsPerComponent: 8, bytesPerRow: decoded.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw LibraryError.unsupportedImage(url.lastPathComponent) }
        context.draw(decoded, in: CGRect(x: 0, y: 0, width: decoded.width, height: decoded.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: decoded.width * decoded.height * 4)
        let globalMultiplier = pow(2.0, adjustments.exposure)
        let brightness = adjustments.brightness.isFinite ? min(1, max(-1, adjustments.brightness)) : 0
        let vibrancy = adjustments.vibrancy.isFinite ? min(1, max(-1, adjustments.vibrancy)) : 0
        let sepia = adjustments.sepia.isFinite ? min(1, max(0, adjustments.sepia)) : 0
        func expose(_ channel: Double, multiplier: Double) -> Double {
            let linear = channel <= 0.04045 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
            let exposed = max(0, linear * multiplier)
            return exposed <= 0.0031308 ? exposed * 12.92 : 1.055 * pow(exposed, 1 / 2.4) - 0.055
        }
        for offset in stride(from: 0, to: decoded.width * decoded.height * 4, by: 4) {
            if offset.isMultiple(of: 65_536) { try Task.checkCancellation() }
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0 else { continue }
            let localEV = mask?.exposure(x: (offset / 4) % decoded.width, y: (offset / 4) / decoded.width,
                                         imageWidth: decoded.width, imageHeight: decoded.height) ?? 0
            let multiplier = localEV == 0 ? globalMultiplier : globalMultiplier * pow(2, localEV)
            let red = expose(Double(pixels[offset]) / (255 * alpha), multiplier: multiplier)
            let green = expose(Double(pixels[offset + 1]) / (255 * alpha), multiplier: multiplier)
            let blue = expose(Double(pixels[offset + 2]) / (255 * alpha), multiplier: multiplier)
            let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
            var lift = 0.0
            if brightness != 0 {
                let luma = min(1, max(0, luminance))
                lift = brightness * luma * (1 - luma)
            }
            var saturation = adjustments.saturation
            if vibrancy != 0 {
                let peak = max(red, green, blue)
                let relativeChroma = peak > 0 ? (peak - min(red, green, blue)) / peak : 0
                saturation *= 1 + vibrancy * (1 - relativeChroma)
            }
            let sepiaLuma = sepia == 0 ? 0 : min(1, max(0, (luminance - 0.5) * adjustments.contrast + 0.5 + lift))
            let warmth = 0.56 * sepiaLuma * (1 - sepiaLuma)
            func encode(_ channel: Double, sepiaTint: Double) -> UInt8 {
                let saturated = luminance + (channel - luminance) * saturation
                let contrasted = (saturated - 0.5) * adjustments.contrast + 0.5 + lift
                let toned = contrasted + sepia * (sepiaLuma + sepiaTint - contrasted)
                return UInt8((min(1, max(0, toned)) * alpha * 255).rounded())
            }
            pixels[offset] = encode(red, sepiaTint: warmth)
            pixels[offset + 1] = encode(green, sepiaTint: warmth * 0.24)
            pixels[offset + 2] = encode(blue, sepiaTint: -warmth * 0.6)
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage(url.lastPathComponent) }
        let toned = try applyTone(result, adjustments: adjustments)
        return (toned, PhotoGeometry(width: decoded.width, height: decoded.height, adjustments: adjustments))
    }
    /// Shared independent sRGB tonal treatment for previews, exports and GPU-free hosts.
    /// Neutral settings bypass conversion; these are not Apple's proprietary RAW formulas.
    static func applyTone(_ source: CGImage, adjustments a: Adjustments) throws -> CGImage {
        guard a.warmth != 0 || a.tint != 0 || a.shadows != 0 || a.highlights != 0 else { return source }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height, bitsPerComponent: 8, bytesPerRow: source.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { throw LibraryError.unsupportedImage("tone adjustment") }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: source.width * source.height * 4)
        func bounded(_ value: Double, _ range: ClosedRange<Double>) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : 0
        }
        let warmth = bounded(a.warmth, -1...1) * 0.15, tint = bounded(a.tint, -1...1) * 0.15
        let shadows = bounded(a.shadows, 0...1), highlights = bounded(a.highlights, -1...0)
        for offset in stride(from: 0, to: source.width * source.height * 4, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0 else { continue }
            let channels = (0..<3).map { Double(pixels[offset + $0]) / (255 * alpha) }
            let luminance = 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
            let tone = shadows * pow(1 - luminance, 2) * luminance + highlights * pow(luminance, 2) * (1 - luminance)
            for index in 0..<3 {
                let balance = index == 0 ? warmth + tint * 0.5 : (index == 1 ? -tint : -warmth + tint * 0.5)
                let value = channels[index] * (1 + balance) + tone
                pixels[offset + index] = UInt8((min(1, max(0, value)) * alpha * 255).rounded())
            }
        }
        guard let result = context.makeImage() else { throw LibraryError.unsupportedImage("tone adjustment") }
        return result
    }
    /// Shared by preview and export, so geometry never depends on GPU availability.
    static func applyGeometry(_ source: CGImage, adjustments: Adjustments) throws -> CGImage {
        try applyGeometry(source, geometry: PhotoGeometry(width: source.width, height: source.height, adjustments: adjustments))
    }

    private static func applyGeometry(_ source: CGImage, geometry: PhotoGeometry) throws -> CGImage {
        var image = source
        if geometry.turns != 0 {
            let size = geometry.rotatedSize
            let context = try geometryContext(width: Int(size.width), height: Int(size.height))
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: -CGFloat(geometry.turns) * .pi / 2)
            context.draw(image, in: CGRect(x: -CGFloat(image.width) / 2, y: -CGFloat(image.height) / 2,
                                           width: CGFloat(image.width), height: CGFloat(image.height)))
            guard let rotated = context.makeImage() else { throw LibraryError.unsupportedImage("rotation") }
            image = rotated
        }
        if geometry.angle != 0 {
            let size = geometry.straightenedSize
            let w = CGFloat(image.width), h = CGFloat(image.height)
            let context = try geometryContext(width: Int(size.width), height: Int(size.height))
            context.translateBy(x: size.width / 2, y: size.height / 2)
            context.rotate(by: -geometry.angle)
            context.draw(image, in: CGRect(x: -w / 2, y: -h / 2, width: w, height: h))
            guard let straightened = context.makeImage() else { throw LibraryError.unsupportedImage("straightening") }
            image = straightened
        }
        if geometry.flipHorizontal || geometry.flipVertical {
            let width = CGFloat(image.width), height = CGFloat(image.height)
            let context = try geometryContext(width: image.width, height: image.height)
            context.translateBy(x: geometry.flipHorizontal ? width : 0, y: geometry.flipVertical ? height : 0)
            context.scaleBy(x: geometry.flipHorizontal ? -1 : 1, y: geometry.flipVertical ? -1 : 1)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let flipped = context.makeImage() else { throw LibraryError.unsupportedImage("flip") }
            image = flipped
        }
        if let rect = geometry.cropRect, let cropped = image.cropping(to: rect) { image = cropped }
        return image
    }
    private static func geometryContext(width: Int, height: Int) throws -> CGContext {
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw LibraryError.unsupportedImage("geometry") }
        context.interpolationQuality = .high
        return context
    }
    public static func dimensions(_ url: URL, adjustments: Adjustments) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { throw LibraryError.unsupportedImage(url.lastPathComponent) }
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let (w, h) = (5...8).contains(orientation) ? (height, width) : (width, height)
        return PhotoGeometry(width: w, height: h, adjustments: adjustments).straightenedSize
    }
    public static func export(_ photo: Photo, repository: LibraryRepository, to destination: URL, options: ExportOptions = ExportOptions()) throws {
        let original = try repository.availableOriginalURL(photo)
        let target = destination.standardizedFileURL.resolvingSymlinksInPath()
        let extensions: [String] = options.format == .original ? [(photo.filename as NSString).pathExtension.lowercased()] : (options.format == .jpeg ? ["jpg", "jpeg"] : (options.format == .tiff ? ["tif", "tiff"] : ["png"]))
        guard extensions.contains(target.pathExtension.lowercased()),
              !target.path.hasPrefix(repository.root.path + "/"), !FileManager.default.fileExists(atPath: target.path),
              !target.pathComponents.contains(where: { ["aplibrary", "aperturelibrary", "photoslibrary", "photolibrary", "app"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else { throw LibraryError.unsafePath }
        let source = CGImageSourceCreateWithURL(original as CFURL, nil)
        let currentIPTC: IPTCMetadata
        if options.xmpSidecar == true || (options.format != .original && options.iptc) {
            let embedded = source.map(LibraryRepository.embeddedIPTC(in:)) ?? IPTCMetadata()
            currentIPTC = photo.iptc?.overriding(embedded) ?? embedded
        } else {
            currentIPTC = IPTCMetadata()
        }
        let sidecar: (url: URL, data: Data)?
        if options.xmpSidecar == true {
            let url = target.deletingPathExtension().appendingPathExtension("xmp")
            let fm = FileManager.default
            guard target.pathExtension.lowercased() != "xmp", !fm.fileExists(atPath: url.path),
                  (try? fm.destinationOfSymbolicLink(atPath: url.path)) == nil else {
                throw XMPMetadata.Failure.sidecarExists(url.lastPathComponent)
            }
            sidecar = (url, try XMPMetadata.encode(photo, iptc: currentIPTC))
        } else {
            sidecar = nil
        }
        if options.format == .original {
            try writeExport(Data(contentsOf: original), to: target, sidecar: sidecar)
            return
        }
        var image = try render(original, adjustments: photo.adjustments)
        if options.maxDimension > 0, max(image.width, image.height) > options.maxDimension {
            let scale = Double(options.maxDimension) / Double(max(image.width, image.height))
            let context = try geometryContext(width: max(1, Int((Double(image.width) * scale).rounded())), height: max(1, Int((Double(image.height) * scale).rounded())))
            context.draw(image, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
            guard let resized = context.makeImage() else { throw LibraryError.unsupportedImage(photo.originalName) }
            image = resized
        }
        var properties: [String: Any] = [:]
        let embedded = source.flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [String: Any] } ?? [:]
        if options.exif {
            var exif = embedded[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
            // Remove stale geometry and embedded maker previews after applying edits.
            exif.removeValue(forKey: kCGImagePropertyExifMakerNote as String)
            if CaptureDateCorrection.parse(photo.captureDate) != nil {
                exif[kCGImagePropertyExifDateTimeOriginal as String] = photo.captureDate
            }
            exif[kCGImagePropertyExifPixelXDimension as String] = image.width
            exif[kCGImagePropertyExifPixelYDimension as String] = image.height
            properties[kCGImagePropertyExifDictionary as String] = exif
            let tiff = embedded[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
            var camera: [String: Any] = [:]
            for key in [kCGImagePropertyTIFFMake, kCGImagePropertyTIFFModel, kCGImagePropertyTIFFArtist, kCGImagePropertyTIFFCopyright, kCGImagePropertyTIFFDateTime] {
                camera[key as String] = tiff[key as String]
            }
            properties[kCGImagePropertyTIFFDictionary as String] = camera
        }
        if options.iptc {
            var iptc = embedded[kCGImagePropertyIPTCDictionary as String] as? [String: Any] ?? [:]
            iptc[kCGImagePropertyIPTCCaptionAbstract as String] = photo.caption
            iptc[kCGImagePropertyIPTCKeywords as String] = photo.keywordNames
            iptc[kCGImagePropertyIPTCStarRating as String] = RatingRules.clamp(photo.rating)
            currentIPTC.writing(to: &iptc)
            properties[kCGImagePropertyIPTCDictionary as String] = iptc
        }
        if options.gps { properties[kCGImagePropertyGPSDictionary as String] = embedded[kCGImagePropertyGPSDictionary as String] }
        properties[kCGImagePropertyOrientation as String] = 1
        properties[kCGImageDestinationLossyCompressionQuality as String] = options.quality.isFinite ? min(1, max(0, options.quality)) : 0.95
        let data = NSMutableData()
        guard let writer = CGImageDestinationCreateWithData(data, options.format.type.identifier as CFString, 1, nil) else { throw LibraryError.unsupportedImage(photo.originalName) }
        CGImageDestinationAddImage(writer, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(writer) else { throw LibraryError.unsupportedImage(photo.originalName) }
        try writeExport(data as Data, to: target, sidecar: sidecar)
    }

    private static func writeExport(_ data: Data, to target: URL, sidecar: (url: URL, data: Data)?) throws {
        if let sidecar { try sidecar.data.write(to: sidecar.url, options: .withoutOverwriting) }
        do {
            try data.write(to: target, options: .withoutOverwriting)
        } catch {
            if let sidecar { try? FileManager.default.removeItem(at: sidecar.url) }
            throw error
        }
    }
}
