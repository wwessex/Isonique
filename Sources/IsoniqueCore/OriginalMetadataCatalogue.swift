import Foundation
import ImageIO

public struct MetadataCatalogueResult: Sendable {
    public let indexed: Int
    public let withValues: Int
    public let issues: [String]
}

public extension LibraryRepository {
    func catalogueEXIF(for ids: Set<UUID>, in library: inout Library) throws -> MetadataCatalogueResult {
        try indexOriginalMetadata(in: &library, at: \.cameraEXIF, includes: {
            ids.contains($0.id) && $0.trashedAt == nil
        }, read: { CameraEXIF(properties: $0) }, hasValue: { !$0.isEmpty })
    }

    func catalogueGPS(for ids: Set<UUID>, in library: inout Library) throws -> MetadataCatalogueResult {
        let originals = Set(library.photos.lazy.filter { ids.contains($0.id) && $0.trashedAt == nil }.map(\.originalID))
        return try indexOriginalMetadata(in: &library, at: \.gpsIndex, includes: {
            originals.contains($0.originalID)
        }, read: GPSIndex.init(properties:), hasValue: { $0.coordinates != nil })
    }

    /// Verify and read each original once. The caller saves the completed draft.
    private func indexOriginalMetadata<Value>(in library: inout Library, at field: WritableKeyPath<Photo, Value?>,
                                              includes: (Photo) -> Bool, read: ([String: Any]) -> Value,
                                              hasValue: (Value) -> Bool) throws -> MetadataCatalogueResult {
        var originals: [UUID: Result<Value, Error>] = [:]
        var updates: [Int: Value] = [:]
        var issues: [String] = []
        for index in library.photos.indices {
            let photo = library.photos[index]
            guard photo[keyPath: field] == nil, includes(photo) else { continue }
            try Task.checkCancellation()
            let id = photo.originalID
            let result = originals[id] ?? Result {
                try autoreleasepool {
                    let source = try verifiedMetadataSource(for: photo)
                    return read(try Self.primaryImageProperties(in: source, name: photo.originalName))
                }
            }
            originals[id] = result
            switch result {
            case .success(let value): updates[index] = value
            case .failure(let error): issues.append(error.localizedDescription)
            }
        }
        try Task.checkCancellation()
        for (index, value) in updates { library.photos[index][keyPath: field] = value }
        return MetadataCatalogueResult(indexed: updates.count, withValues: updates.values.filter(hasValue).count, issues: issues)
    }
}
