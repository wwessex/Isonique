import Foundation

public enum BatchKeywordMode: String, CaseIterable, Identifiable {
    case unchanged = "Leave Unchanged"
    case append = "Append"
    case replace = "Replace"

    public var id: Self { self }
}

public struct BatchMetadataChange: Codable, Equatable {
    public let photoID: UUID
    public let caption: String?
    public let keywords: String?
}

public struct BatchMetadataReview: Identifiable {
    public let id = UUID()
    private let targets: [Target]

    private struct Target {
        let id: UUID
        let name: String
        let caption: String
        let keywords: String
    }

    public init(photos: [Photo]) {
        targets = photos.map { Target(id: $0.id, name: $0.displayName, caption: $0.caption, keywords: $0.keywords) }
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

    public func preview(caption: String?, keywordMode: BatchKeywordMode, keywords: String) -> Preview {
        var inputKeys: Set<String> = []
        let input = Self.keywordValues(keywords).filter { inputKeys.insert(Self.keywordKey($0)).inserted }
        let replacement = input.joined(separator: ", ")
        let rows = targets.compactMap { target -> Row? in
            let newCaption = caption != target.caption ? caption : nil
            let newKeywords: String?
            switch keywordMode {
            case .unchanged:
                newKeywords = nil
            case .append:
                let existing = Self.keywordValues(target.keywords)
                let known = Set(existing.map(Self.keywordKey))
                let additions = input.filter { !known.contains(Self.keywordKey($0)) }
                newKeywords = additions.isEmpty ? nil : (existing + additions).joined(separator: ", ")
            case .replace:
                newKeywords = replacement == target.keywords ? nil : replacement
            }
            guard newCaption != nil || newKeywords != nil else { return nil }
            return Row(name: target.name,
                       before: BatchMetadataChange(photoID: target.id,
                                                   caption: newCaption.map { _ in target.caption },
                                                   keywords: newKeywords.map { _ in target.keywords }),
                       after: BatchMetadataChange(photoID: target.id, caption: newCaption, keywords: newKeywords))
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
              }) else { return nil }
        return library.replaceBatchMetadata(preview.rows.map(\.after))
    }

    private static func keywordValues(_ input: String) -> [String] {
        input.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func keywordKey(_ value: String) -> String {
        value.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Library {
    mutating func replaceBatchMetadata(_ changes: [BatchMetadataChange]) -> [BatchMetadataChange]? {
        applyPhotoFieldChanges(changes, photoID: \.photoID) { photo, change in
            let previous = BatchMetadataChange(photoID: photo.id,
                                               caption: change.caption.map { _ in photo.caption },
                                               keywords: change.keywords.map { _ in photo.keywords })
            if let caption = change.caption { photo.caption = caption }
            if let keywords = change.keywords { photo.keywords = keywords }
            return previous
        }
    }
}
