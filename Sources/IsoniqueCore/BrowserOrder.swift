import Foundation

/// Per-container photo order. Keys are stable Browser scopes such as `all`,
/// `project:<uuid>` and `album:<uuid>`.
public struct BrowserOrderState: Codable, Equatable {
    public private(set) var orders: [String: [UUID]]

    public init(orders: [String: [UUID]] = [:]) {
        self.orders = orders.filter { !$0.value.isEmpty }
    }

    public var isEmpty: Bool { orders.isEmpty }

    public func ids(in scope: String) -> [UUID] { orders[scope] ?? [] }

    public func ordered(_ photos: [Photo], in scope: String) -> [Photo] {
        let positions = Dictionary(uniqueKeysWithValues: ids(in: scope).enumerated().map { ($0.element, $0.offset) })
        return photos.sorted { lhs, rhs in
            switch (positions[lhs.id], positions[rhs.id]) {
            case let (left?, right?): return left == right ? lhs.id.uuidString < rhs.id.uuidString : left < right
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                return lhs.importedAt == rhs.importedAt
                    ? lhs.id.uuidString < rhs.id.uuidString
                    : lhs.importedAt < rhs.importedAt
            }
        }
    }

    @discardableResult
    public mutating func move(_ moving: [UUID], before target: UUID?, in scope: String,
                              seededBy seed: [UUID]) -> Bool {
        let available = Set(seed)
        let moved = moving.filter(available.contains).uniqued()
        guard !moved.isEmpty else { return false }
        var order = ids(in: scope).filter(available.contains)
        for id in seed where !order.contains(id) { order.append(id) }
        let previous = order
        order.removeAll { moved.contains($0) }
        let insertion = target.flatMap { order.firstIndex(of: $0) } ?? order.endIndex
        order.insert(contentsOf: moved, at: insertion)
        guard order != previous else { return false }
        orders[scope] = order
        return true
    }

    public mutating func set(_ ids: [UUID], in scope: String) {
        let unique = ids.uniqued()
        if unique.isEmpty { orders[scope] = nil }
        else { orders[scope] = unique }
    }

    public mutating func remove(_ photoIDs: Set<UUID>) {
        for scope in Array(orders.keys) {
            let remaining = (orders[scope] ?? []).filter { !photoIDs.contains($0) }
            orders[scope] = remaining.isEmpty ? nil : remaining
        }
    }

    func validateStructure() throws {
        for (scope, ids) in orders {
            guard Self.isSupportedScope(scope), Set(ids).count == ids.count else {
                throw LibraryError.integrity("manual Browser order")
            }
        }
    }

    static func isSupportedScope(_ scope: String) -> Bool {
        if scope == "all" { return true }
        let parts = scope.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == "project" || parts[0] == "album" else { return false }
        return UUID(uuidString: String(parts[1])) != nil
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
