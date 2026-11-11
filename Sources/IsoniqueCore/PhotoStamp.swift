import Foundation

/// A stamp can change recipes and metadata together. History restores only the affected fields and groups.
public struct PhotoStampChange: Codable, Equatable {
    private let metadata: BatchMetadataChange
    private let groups: Set<AdjustmentGroup>
    private let adjustments: Adjustments?
    private let rating: Int?

    public var photoID: UUID { metadata.photoID }
    var containsSpotRemoval: Bool { adjustments?.spotRemovals.isEmpty == false }

    fileprivate init(previous: Photo, current: Photo, groups: Set<AdjustmentGroup>) {
        let iptc = IPTCField.allCases.compactMap { field -> IPTCFieldEdit? in
            let old = previous.iptc?[field]
            return old != current.iptc?[field] ? IPTCFieldEdit(field: field, values: old) : nil
        }
        metadata = BatchMetadataChange(photoID: previous.id,
                                       caption: previous.caption != current.caption ? previous.caption : nil,
                                       keywords: previous.keywords != current.keywords ? previous.keywords : nil,
                                       keywordPaths: previous.keywordPaths != current.keywordPaths ? previous.keywordPaths ?? [] : nil,
                                       iptc: iptc.isEmpty ? nil : iptc)
        self.groups = groups.filter { group in
            previous.adjustments.stamping(onto: current.adjustments, groups: [group]) != current.adjustments
        }
        adjustments = self.groups.isEmpty ? nil : previous.adjustments.stamping(onto: Adjustments(), groups: self.groups)
        rating = previous.rating != current.rating ? previous.rating : nil
    }

    func applying(to photo: inout Photo) -> Self {
        let previous = photo
        _ = metadata.applying(to: &photo)
        if let adjustments { photo.adjustments = adjustments.stamping(onto: photo.adjustments, groups: groups) }
        if let rating { photo.rating = rating }
        return Self(previous: previous, current: photo, groups: groups)
    }
}

public extension Library {
    mutating func stamp(_ lifted: LiftedSettings, groups: Set<AdjustmentGroup>,
                        metadata: Set<StampMetadata>, onto targets: Set<UUID>) -> [PhotoStampChange] {
        var changes: [PhotoStampChange] = []
        for index in photos.indices where photos[index].trashedAt == nil && targets.contains(photos[index].id) {
            let previous = photos[index]
            let current = lifted.applying(to: previous, groups: groups, metadata: metadata)
            guard current != previous else { continue }
            photos[index] = current
            changes.append(PhotoStampChange(previous: previous, current: current, groups: groups))
        }
        return changes
    }
}
