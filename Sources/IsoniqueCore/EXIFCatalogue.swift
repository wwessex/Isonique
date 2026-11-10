import Foundation

public struct EXIFCatalogueResult: Sendable {
    public let indexed: Int
    public let withCaptureSettings: Int
    public let issues: [String]
}

public extension LibraryRepository {
    /// Index a fixed selection and leave the save to the caller's existing catalogue transaction.
    func catalogueEXIF(for ids: Set<UUID>, in library: inout Library) throws -> EXIFCatalogueResult {
        var originals: [UUID: Result<CameraEXIF, Error>] = [:]
        var updates: [Int: CameraEXIF] = [:]
        var issues: [String] = []
        for index in library.photos.indices {
            let photo = library.photos[index]
            guard ids.contains(photo.id), photo.trashedAt == nil, photo.cameraEXIF == nil else { continue }
            try Task.checkCancellation()
            let id = photo.originalID
            let result = originals[id] ?? Result {
                try autoreleasepool {
                    try Self.cameraEXIF(in: verifiedMetadataSource(for: photo), name: photo.originalName)
                }
            }
            originals[id] = result
            switch result {
            case .success(let exif): updates[index] = exif
            case .failure(let error): issues.append(error.localizedDescription)
            }
        }
        try Task.checkCancellation()
        for (index, exif) in updates { library.photos[index].cameraEXIF = exif }
        return EXIFCatalogueResult(indexed: updates.count,
                                   withCaptureSettings: updates.values.filter { !$0.isEmpty }.count,
                                   issues: issues)
    }
}
