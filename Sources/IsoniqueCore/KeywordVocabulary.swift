import Foundation

/// A vocabulary term qualified by its ancestors, independent of a particular vocabulary file.
public struct KeywordPath: Codable, Hashable {
    public let components: [String]

    public init?(_ components: [String]) {
        guard (1...32).contains(components.count), components.allSatisfy(KeywordVocabulary.validName) else { return nil }
        self.components = components
    }

    public var name: String { components[components.count - 1] }
    public var title: String { components.joined(separator: " › ") }
    private var key: [String] { components.map(KeywordList.key) }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.key == rhs.key }
    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    public func isWithin(_ branch: Self) -> Bool { key.starts(with: branch.key) }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        let components = try value.decode([String].self)
        guard let path = Self(components) else {
            throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid vocabulary keyword path")
        }
        self = path
    }

    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        try value.encode(components)
    }
}

public struct KeywordVocabulary: Codable, Equatable {
    public struct Entry: Codable, Equatable, Identifiable {
        public let id: UUID
        public fileprivate(set) var name: String
        public fileprivate(set) var children: [Entry]

        fileprivate init(name: String, children: [Entry] = []) {
            id = UUID()
            self.name = name
            self.children = children
        }
    }

    public private(set) var roots: [Entry] = []

    public init() {}

    public init(text: String) throws {
        let text = text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        var rows: [(depth: Int, name: String)] = []
        for (index, line) in lines.enumerated() {
            let depth = line.prefix(while: { $0 == "\t" }).count
            let content = line.dropFirst(depth)
            let name = content.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            let deepestAllowed = (rows.last?.depth ?? -1) + 1
            guard depth < 32, depth <= deepestAllowed, !content.contains("\t"), Self.validName(name) else {
                throw KeywordVocabularyError.invalidLine(index + 1)
            }
            rows.append((depth, name))
        }

        var index = 0
        func readChildren(at depth: Int) -> [Entry] {
            var entries: [Entry] = []
            while index < rows.count, rows[index].depth == depth {
                let name = rows[index].name
                index += 1
                entries.append(Entry(name: name, children: readChildren(at: depth + 1)))
            }
            return entries
        }
        let entries = readChildren(at: 0)
        Self.merge(entries, into: &roots)
    }

    public var text: String {
        func write(_ entries: [Entry], indent: String) -> String {
            entries.map { indent + $0.name + "\n" + write($0.children, indent: indent + "\t") }.joined()
        }
        return write(roots, indent: "")
    }

    @discardableResult
    public mutating func merge(_ vocabulary: Self) -> Int {
        Self.merge(vocabulary.roots, into: &roots)
    }

    public func entry(_ id: UUID) -> Entry? {
        func find(in entries: [Entry]) -> Entry? {
            for entry in entries {
                if entry.id == id { return entry }
                if let child = find(in: entry.children) { return child }
            }
            return nil
        }
        return find(in: roots)
    }

    public func path(to id: UUID) -> KeywordPath? {
        func find(in entries: [Entry], ancestors: [String]) -> KeywordPath? {
            for entry in entries {
                let components = ancestors + [entry.name]
                if entry.id == id { return KeywordPath(components) }
                if let child = find(in: entry.children, ancestors: components) { return child }
            }
            return nil
        }
        return find(in: roots, ancestors: [])
    }

    public var paths: [KeywordPath] {
        func collect(_ entries: [Entry], ancestors: [String]) -> [KeywordPath] {
            entries.flatMap { entry -> [KeywordPath] in
                let components = ancestors + [entry.name]
                guard let path = KeywordPath(components) else { return [] }
                return [path] + collect(entry.children, ancestors: components)
            }
        }
        return collect(roots, ancestors: [])
    }

    @discardableResult
    public mutating func add(_ name: String, under parentID: UUID? = nil) throws -> UUID {
        let entry = Entry(name: try Self.checkedName(name))
        func insert(into siblings: inout [Entry]) throws {
            try Self.checkDuplicate(entry.name, in: siblings)
            siblings.append(entry)
        }
        if let parentID {
            let found = try Self.edit(&roots, id: parentID) { siblings, index, depth in
                guard depth < 31 else { throw KeywordVocabularyError.tooDeep }
                try insert(into: &siblings[index].children)
            }
            guard found else { throw KeywordVocabularyError.missingEntry }
        } else {
            try insert(into: &roots)
        }
        return entry.id
    }

    public mutating func rename(_ id: UUID, to name: String) throws {
        let name = try Self.checkedName(name)
        let found = try Self.edit(&roots, id: id) { siblings, index, _ in
            try Self.checkDuplicate(name, in: siblings, excluding: id)
            siblings[index].name = name
        }
        guard found else { throw KeywordVocabularyError.missingEntry }
    }

    public mutating func delete(_ id: UUID) throws {
        guard Self.edit(&roots, id: id, update: { siblings, index, _ in siblings.remove(at: index) }) else {
            throw KeywordVocabularyError.missingEntry
        }
    }

    @discardableResult
    private static func merge(_ incoming: [Entry], into existing: inout [Entry]) -> Int {
        var positions = Dictionary(existing.enumerated().map { (KeywordList.key($0.element.name), $0.offset) },
                                   uniquingKeysWith: { first, _ in first })
        var added = 0
        for entry in incoming {
            let key = KeywordList.key(entry.name)
            if let index = positions[key] {
                added += merge(entry.children, into: &existing[index].children)
            } else {
                positions[key] = existing.count
                var newEntry = Entry(name: entry.name)
                added += 1 + merge(entry.children, into: &newEntry.children)
                existing.append(newEntry)
            }
        }
        return added
    }

    private static func edit(_ entries: inout [Entry], id: UUID, depth: Int = 0,
                             update: (inout [Entry], Int, Int) throws -> Void) rethrows -> Bool {
        for index in entries.indices {
            if entries[index].id == id {
                try update(&entries, index, depth)
                return true
            }
            if try edit(&entries[index].children, id: id, depth: depth + 1, update: update) { return true }
        }
        return false
    }

    fileprivate static func validName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains(",") && name.rangeOfCharacter(from: .newlines) == nil
            && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
    }

    private static func checkedName(_ value: String) throws -> String {
        let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validName(name) else { throw KeywordVocabularyError.invalidName }
        return name
    }

    private static func checkDuplicate(_ name: String, in siblings: [Entry], excluding id: UUID? = nil) throws {
        let key = KeywordList.key(name)
        if siblings.contains(where: { $0.id != id && KeywordList.key($0.name) == key }) {
            throw KeywordVocabularyError.duplicateName
        }
    }
}

public enum KeywordVocabularyError: LocalizedError {
    case invalidLine(Int), invalidName, duplicateName, missingEntry, tooDeep, invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .invalidLine(let line): return "Invalid keyword or tab indentation on line \(line)."
        case .invalidName: return "Enter a keyword without commas, tabs or line breaks."
        case .duplicateName: return "This branch already contains that keyword."
        case .missingEntry: return "That vocabulary entry is no longer available."
        case .tooDeep: return "The vocabulary supports up to 32 levels."
        case .invalidEncoding: return "Choose a UTF-8 keyword list."
        }
    }
}
