import CryptoKit
import Foundation
import ImageIO

public struct InheritedIPTCReview: Identifiable {
    public struct Issue: Identifiable {
        public let id: UUID
        public let name: String
        public let reason: String
    }

    public let batch: BatchMetadataReview
    public let preview: BatchMetadataReview.Preview
    public let issues: [Issue]
    public let originalCount: Int
    public var id: UUID { batch.id }
}

public extension LibraryRepository {
    /// Review a fixed selection. Store only the verified metadata, with one read per shared original.
    func reviewInheritedIPTC(for photos: [Photo]) throws -> InheritedIPTCReview {
        let batch = BatchMetadataReview(photos: photos)
        var originals: [UUID: Result<IPTCMetadata, Error>] = [:]
        var metadata: [UUID: IPTCMetadata] = [:]
        var issues: [InheritedIPTCReview.Issue] = []
        for photo in photos where photo.hasUncataloguedIPTC {
            try Task.checkCancellation()
            let id = photo.originalID
            let result = originals[id] ?? Result { try autoreleasepool { try Self.embeddedIPTC(in: verifiedMetadataSource(for: photo)) } }
            originals[id] = result
            switch result {
            case .success(let fields):
                metadata[photo.id] = fields
            case .failure(let error):
                issues.append(.init(id: photo.id, name: photo.displayName, reason: error.localizedDescription))
            }
        }
        try Task.checkCancellation()
        return InheritedIPTCReview(batch: batch, preview: batch.previewInheritedIPTC(metadata),
                                   issues: issues, originalCount: originals.count)
    }

    internal func verifiedMetadataSource(for photo: Photo) throws -> CGImageSource {
        let url = try availableOriginalURL(photo)
        // Read one original at a time and give ImageIO the same bytes we verified.
        let data = try Data(contentsOf: url, options: .uncached)
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard hash == photo.sha256 else { throw LibraryError.integrity(photo.originalName) }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { throw LibraryError.unsupportedImage(photo.originalName) }
        return source
    }
}
