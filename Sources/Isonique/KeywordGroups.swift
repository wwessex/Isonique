import Foundation
import IsoniqueCore

struct KeywordGroup: Codable, Equatable, Identifiable {
    let id: UUID
    let name: String
    let keywords: [String]

    init(id: UUID = UUID(), name: String, keywordText: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = KeywordList.uniqueValues(keywordText)
        guard !trimmed.isEmpty else { throw KeywordGroupError.missingName }
        guard !values.isEmpty else { throw KeywordGroupError.missingKeywords }
        self.id = id
        self.name = trimmed
        self.keywords = values
    }

    var keywordText: String { keywords.joined(separator: ", ") }
}

enum KeywordGroupError: LocalizedError {
    case missingName, missingKeywords, duplicateName

    var errorDescription: String? {
        switch self {
        case .missingName: return "Enter a name for the keyword group."
        case .missingKeywords: return "Enter at least one keyword."
        case .duplicateName: return "A keyword group with this name already exists."
        }
    }
}

struct KeywordGroupPreferences: Codable {
    static let key = "metadata.keywordGroups"
    static let controlsKey = "metadata.showKeywordControls"
    private(set) var groups: [KeywordGroup] = []
    private(set) var activeID: UUID?

    var active: KeywordGroup? { groups.first { $0.id == activeID } }

    static func load(from preferences: UserDefaults) -> Self {
        guard let data = preferences.data(forKey: key),
              var saved = try? JSONDecoder().decode(Self.self, from: data) else { return Self() }
        var ids: Set<UUID> = []
        var names: Set<String> = []
        saved.groups = saved.groups.compactMap { group in
            guard let clean = try? KeywordGroup(id: group.id, name: group.name, keywordText: group.keywordText),
                  !ids.contains(clean.id), !names.contains(nameKey(clean.name)) else { return nil }
            ids.insert(clean.id)
            names.insert(nameKey(clean.name))
            return clean
        }
        saved.sortGroups()
        if saved.active == nil { saved.activeID = saved.groups.first?.id }
        return saved
    }

    mutating func save(_ group: KeywordGroup) throws {
        guard !groups.contains(where: { $0.id != group.id && Self.nameKey($0.name) == Self.nameKey(group.name) }) else {
            throw KeywordGroupError.duplicateName
        }
        groups.removeAll { $0.id == group.id }
        groups.append(group)
        sortGroups()
        activeID = group.id
    }

    mutating func select(_ id: UUID) {
        if groups.contains(where: { $0.id == id }) { activeID = id }
    }

    mutating func delete(_ id: UUID) {
        groups.removeAll { $0.id == id }
        if activeID == id { activeID = groups.first?.id }
    }

    func write(to preferences: UserDefaults) throws {
        preferences.set(try JSONEncoder().encode(self), forKey: Self.key)
    }

    private mutating func sortGroups() {
        groups.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func nameKey(_ name: String) -> String {
        name.folding(options: .caseInsensitive, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Workspace {
    func saveKeywordGroup(_ group: KeywordGroup) throws {
        try updateKeywordGroups { try $0.save(group) }
        showKeywordControls = true
    }

    func deleteKeywordGroup(_ id: UUID) throws {
        try updateKeywordGroups { $0.delete(id) }
    }

    func selectKeywordGroup(_ id: UUID) {
        do { try updateKeywordGroups { $0.select(id) } }
        catch { self.error = error.localizedDescription }
    }

    private func updateKeywordGroups(_ update: (inout KeywordGroupPreferences) throws -> Void) throws {
        var updated = KeywordGroupPreferences.load(from: preferences)
        try update(&updated)
        try updated.write(to: preferences)
        keywordGroups = updated
    }

    @discardableResult
    func addKeywords(_ keywords: String) -> Bool {
        applyKeywordChange(noChange: "Selected photos already have these keywords") { review in
            review.preview(caption: nil, keywordMode: .append, keywords: keywords)
        }
    }

    @discardableResult
    func removeKeywords(_ keywords: String) -> Bool {
        applyKeywordChange(noChange: "Selected photos don’t have these keywords") { review in
            review.previewRemovingKeywords(keywords)
        }
    }

    private func applyKeywordChange(noChange: String, preview makePreview: (BatchMetadataReview) -> BatchMetadataReview.Preview) -> Bool {
        let targets = metadataEditingTargets
        guard !targets.isEmpty else { return false }
        let review = BatchMetadataReview(photos: targets)
        let preview = makePreview(review)
        guard !preview.rows.isEmpty else {
            status = noChange
            return false
        }
        return applyBatchMetadata(preview, for: review)
    }
}
