import Foundation

public enum BatchKeywordMode: String, CaseIterable, Codable, Identifiable {
    case unchanged = "Leave Unchanged"
    case append = "Append"
    case replace = "Replace"

    public var id: Self { self }

    func replacement(for current: String, using input: [String]) -> String? {
        switch self {
        case .unchanged:
            return nil
        case .append:
            let existing = KeywordList.values(current)
            let known = Set(existing.map(KeywordList.key))
            let additions = input.filter { !known.contains(KeywordList.key($0)) }
            return additions.isEmpty ? nil : (existing + additions).joined(separator: ", ")
        case .replace:
            let replacement = input.joined(separator: ", ")
            return replacement == current ? nil : replacement
        }
    }
}

public struct BatchMetadataChange: Codable, Equatable {
    public let photoID: UUID
    public let caption: String?
    public let keywords: String?
    public let keywordPaths: [KeywordPath]?
    public let iptc: [IPTCFieldEdit]?
}

public struct BatchMetadataReview: Identifiable {
    public let id = UUID()
    private let targets: [Target]

    private struct Target {
        let id: UUID
        let name: String
        let caption: String
        let keywords: String
        let keywordPaths: [KeywordPath]
        let iptc: IPTCMetadata?
    }

    public init(photos: [Photo]) {
        targets = photos.map {
            Target(id: $0.id, name: $0.displayName, caption: $0.caption,
                   keywords: $0.keywords, keywordPaths: $0.keywordPaths ?? [], iptc: $0.iptc)
        }
    }

    public var photoCount: Int { targets.count }

    public struct Row: Identifiable {
        public let name: String
        public let before: BatchMetadataChange
        public let after: BatchMetadataChange
        public var id: UUID { after.photoID }
    }

    public struct Preview {
        fileprivate let reviewID: UUID
        public let rows: [Row]
    }

    public func preview(caption: String?, keywordMode: BatchKeywordMode, keywords: String,
                        iptc: IPTCMetadata = IPTCMetadata()) -> Preview {
        preview(MetadataPresetValues(caption: caption, keywordMode: keywordMode, keywords: keywords, iptc: iptc))
    }

    public func preview(_ values: MetadataPresetValues) -> Preview {
        let input = KeywordList.uniqueValues(values.keywords)
        return preview(caption: values.caption, iptc: { _ in values.iptc }, keywordChange: {
            values.keywordMode.replacement(for: $0, using: input)
        })
    }

    public func previewRemovingKeywords(_ keywords: String) -> Preview {
        let removedKeys = Set(KeywordList.values(keywords).map(KeywordList.key))
        return preview(caption: nil, keywordChange: { keywords in
            let existing = KeywordList.values(keywords)
            let kept = existing.filter { !removedKeys.contains(KeywordList.key($0)) }
            return kept.count == existing.count ? nil : kept.joined(separator: ", ")
        })
    }

    public func previewKeywordPath(_ path: KeywordPath, adding: Bool) -> Preview {
        preview(caption: nil, keywordPathChange: { current in
            if adding { return current.contains(path) ? nil : current + [path] }
            let remaining = current.filter { $0 != path }
            return remaining.count == current.count ? nil : remaining
        })
    }

    func previewInheritedIPTC(_ originals: [UUID: IPTCMetadata]) -> Preview {
        preview(caption: nil, iptc: { target in
            guard let embedded = originals[target.id] else { return IPTCMetadata() }
            var result = IPTCMetadata()
            for field in IPTCField.allCases where target.iptc?[field] == nil {
                result[field] = embedded[field]
            }
            return result
        })
    }

    private func preview(caption: String?, iptc: (Target) -> IPTCMetadata = { _ in IPTCMetadata() }, keywordChange: (String) -> String? = { _ in nil },
                         keywordPathChange: ([KeywordPath]) -> [KeywordPath]? = { _ in nil }) -> Preview {
        let rows = targets.compactMap { target -> Row? in
            let newCaption = caption != target.caption ? caption : nil
            let newKeywords = keywordChange(target.keywords)
            let newPaths = keywordPathChange(target.keywordPaths)
            let fields = iptc(target)
            let iptcEdits = IPTCField.allCases.compactMap { field -> IPTCFieldEdit? in
                guard let values = fields[field], values != target.iptc?[field] else { return nil }
                return IPTCFieldEdit(field: field, values: values)
            }
            let previousIPTC = iptcEdits.map { IPTCFieldEdit(field: $0.field, values: target.iptc?[$0.field]) }
            guard newCaption != nil || newKeywords != nil || newPaths != nil || !iptcEdits.isEmpty else { return nil }
            return Row(name: target.name,
                       before: BatchMetadataChange(photoID: target.id,
                                                   caption: newCaption.map { _ in target.caption },
                                                   keywords: newKeywords.map { _ in target.keywords },
                                                   keywordPaths: newPaths.map { _ in target.keywordPaths },
                                                   iptc: previousIPTC.isEmpty ? nil : previousIPTC),
                       after: BatchMetadataChange(photoID: target.id, caption: newCaption, keywords: newKeywords,
                                                  keywordPaths: newPaths, iptc: iptcEdits.isEmpty ? nil : iptcEdits))
        }
        return Preview(reviewID: id, rows: rows)
    }

    /// Apply the reviewed values only if the selected records still have the metadata shown in the review.
    public func apply(_ preview: Preview, to library: inout Library) -> [BatchMetadataChange]? {
        guard preview.reviewID == id, !preview.rows.isEmpty else { return nil }
        let expected = Dictionary(uniqueKeysWithValues: targets.map { ($0.id, $0) })
        let current = library.activePhotos.filter { expected[$0.id] != nil }
        guard current.count == expected.count,
              current.allSatisfy({ photo in
                  let target = expected[photo.id]
                  return photo.caption == target?.caption && photo.keywords == target?.keywords
                      && (photo.keywordPaths ?? []) == target?.keywordPaths && photo.iptc == target?.iptc
              }) else { return nil }
        return library.replaceBatchMetadata(preview.rows.map(\.after))
    }
}

public enum KeywordList {
    /// Clean comma-separated input and keep the first spelling and position of each keyword.
    public static func uniqueValues(_ input: String) -> [String] {
        var seen: Set<String> = []
        return values(input).filter { seen.insert(key($0)).inserted }
    }

    static func values(_ input: String) -> [String] {
        input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func key(_ value: String) -> String {
        value.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Photo {
    var keywordNames: [String] {
        var names = KeywordList.values(keywords)
        guard let keywordPaths, !keywordPaths.isEmpty else { return names }
        var seen = Set(names.map(KeywordList.key))
        for path in keywordPaths where seen.insert(KeywordList.key(path.name)).inserted {
            names.append(path.name)
        }
        return names
    }

    public var keywordSearchText: String {
        guard let keywordPaths, !keywordPaths.isEmpty else { return keywords }
        return ([keywords] + keywordPaths.map(\.title)).joined(separator: " ")
    }
}

extension BatchMetadataChange {
    func applying(to photo: inout Photo) -> Self {
        let previous = Self(photoID: photo.id,
                            caption: caption.map { _ in photo.caption },
                            keywords: keywords.map { _ in photo.keywords },
                            keywordPaths: keywordPaths.map { _ in photo.keywordPaths ?? [] },
                            iptc: iptc.map { photo.applyIPTC($0) })
        if let caption { photo.caption = caption }
        if let keywords { photo.keywords = keywords }
        if let keywordPaths { photo.keywordPaths = keywordPaths.isEmpty ? nil : keywordPaths }
        return previous
    }
}

extension Library {
    mutating func replaceBatchMetadata(_ changes: [BatchMetadataChange]) -> [BatchMetadataChange]? {
        applyPhotoFieldChanges(changes, photoID: \.photoID) { photo, change in change.applying(to: &photo) }
    }
}
