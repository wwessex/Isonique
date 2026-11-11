import Foundation

public extension AdjustmentGroup {
    var isSpatial: Bool {
        switch self {
        case .geometry, .localBrush, .retouch, .redEye: true
        default: false
        }
    }

    static var nonSpatialGroups: Set<AdjustmentGroup> {
        Set(allCases.filter { !$0.isSpatial })
    }
}

public struct CustomAdjustmentPreset: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var adjustments: Adjustments
    public var groups: Set<AdjustmentGroup>

    public init(id: UUID = UUID(), name: String, adjustments: Adjustments,
                groups: Set<AdjustmentGroup> = AdjustmentGroup.nonSpatialGroups) {
        self.id = id
        self.name = name
        self.adjustments = adjustments
        self.groups = groups
    }

    public var includesSpatialAdjustments: Bool { groups.contains(where: \.isSpatial) }

    public func applying(to target: Adjustments) -> Adjustments {
        adjustments.stamping(onto: target, groups: groups)
    }

    public func changedGroups(in target: Adjustments) -> Set<AdjustmentGroup> {
        Set(groups.filter { group in
            adjustments.stamping(onto: target, groups: [group]) != target
        })
    }

    private enum CodingKeys: String, CodingKey { case id, name, adjustments, recipe, groups }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try values.decode(String.self, forKey: .name)
        adjustments = try values.decodeIfPresent(Adjustments.self, forKey: .adjustments)
            ?? values.decode(Adjustments.self, forKey: .recipe)
        if let names = try values.decodeIfPresent([String].self, forKey: .groups) {
            groups = Set(names.compactMap(AdjustmentGroup.init(rawValue:)))
        } else {
            groups = AdjustmentGroup.nonSpatialGroups
        }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(name, forKey: .name)
        try values.encode(adjustments, forKey: .adjustments)
        try values.encode(groups.map(\.rawValue).sorted(), forKey: .groups)
    }
}
