import Foundation

public struct MetadataPresetValues: Codable, Equatable {
    public var caption: String?
    public var keywordMode: BatchKeywordMode
    public var keywords: String
    public var iptc: IPTCMetadata

    public init(caption: String? = nil, keywordMode: BatchKeywordMode = .unchanged,
                keywords: String = "", iptc: IPTCMetadata = IPTCMetadata()) {
        self.caption = caption
        self.keywordMode = keywordMode
        self.keywords = keywords
        self.iptc = iptc
    }

    public var hasChanges: Bool {
        caption != nil || !iptc.isEmpty || keywordMode == .replace
            || (keywordMode == .append && !KeywordList.uniqueValues(keywords).isEmpty)
    }

    func applying(to source: Photo) -> Photo {
        var photo = source
        if let caption { photo.caption = caption }
        if let keywords = keywordMode.replacement(for: photo.keywords, using: KeywordList.uniqueValues(keywords)) {
            photo.keywords = keywords
        }
        if !iptc.isEmpty { photo.iptc = iptc.overriding(photo.iptc ?? IPTCMetadata()) }
        return photo
    }
}

public struct MetadataPreset: Codable, Identifiable, Equatable {
    public let id: UUID
    public let name: String
    public let values: MetadataPresetValues

    public init(id: UUID = UUID(), name: String, values: MetadataPresetValues) {
        self.id = id
        self.name = name
        self.values = values
    }
}
