import Foundation

/// Rules use the current photo values, so album membership updates after every edit.
public struct SmartAlbumRule: Codable, Equatable {
    public var minimumRating: Int
    public var ratingFilterIndex: Int?
    public var flaggedOnly: Bool
    public var text: String
    public init(minimumRating: Int = 0, flaggedOnly: Bool = false, text: String = "") {
        self.minimumRating = minimumRating; self.flaggedOnly = flaggedOnly; self.text = text
    }
    public func includes(_ photo: Photo) -> Bool {
        let matchesRatingAndFlag: Bool
        if let index = ratingFilterIndex, let filter = RatingFilter(rawValue: index) {
            matchesRatingAndFlag = BrowserFilterRules.includes(rating: photo.rating, flagged: photo.flagged, ratingFilter: filter, flaggedOnly: flaggedOnly)
        } else {
            // Preserve saved threshold rules, including values outside today's UI range.
            matchesRatingAndFlag = photo.rating >= minimumRating && (!flaggedOnly || photo.flagged)
        }
        return matchesRatingAndFlag &&
        (text.isEmpty || [photo.originalName, photo.caption, photo.keywords, photo.camera].joined(separator: " ").localizedCaseInsensitiveContains(text))
    }
    public var selectedRatingFilter: RatingFilter {
        ratingFilterIndex.flatMap(RatingFilter.init(rawValue:)) ?? (minimumRating == -1 ? .all : RatingFilter(rawValue: minimumRating) ?? .unratedAndAbove)
    }
    public mutating func setRatingFilter(_ filter: RatingFilter) {
        ratingFilterIndex = filter.rawValue
        // Retain a readable threshold for previous app versions. Exact-only filters
        // require this version; older versions cannot represent them.
        switch filter {
        case .all, .rejected: minimumRating = RatingRules.rejected
        case .unrated: minimumRating = RatingRules.unrated
        default: minimumRating = filter.rawValue
        }
    }
}

public enum StackRules {
    public static func canStack(photoCount: Int) -> Bool { photoCount >= 2 }
}

/// Named recipes share the immutable original; restoring one preserves current metadata.
public struct PhotoVersion: Codable, Identifiable, Equatable {
    public var id = UUID()
    public var name: String
    public var createdAt = Date()
    public var adjustments: Adjustments
    public init(name: String, adjustments: Adjustments) { self.name = name; self.adjustments = adjustments }
}
public extension Library {
    /// Applies a batch to a stable ID snapshot, even if edits change current filters.
    mutating func updatePhotos(_ ids: Set<UUID>, change: (inout Photo) -> Void) -> [Photo] {
        var previous: [Photo] = []
        for index in photos.indices where ids.contains(photos[index].id) {
            let old = photos[index]
            change(&photos[index]); photos[index].rating = RatingRules.clamp(photos[index].rating)
            if old != photos[index] { previous.append(old) }
        }
        return previous
    }
}

public enum BatchExport {
    /// Validate before creating anything; refuse existing folders and library locations.
    public static func prepareDirectory(_ folder: URL, repository: LibraryRepository) throws {
        let target = folder.standardizedFileURL.resolvingSymlinksInPath()
        guard target != repository.root, !target.path.hasPrefix(repository.root.path + "/"),
              !FileManager.default.fileExists(atPath: target.path),
              !target.pathComponents.contains(where: { ["aplibrary", "aperturelibrary", "photoslibrary", "photolibrary", "app"].contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }) else { throw LibraryError.unsafePath }
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
    }
}
