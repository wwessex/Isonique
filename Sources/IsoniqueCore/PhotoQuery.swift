import Foundation

public enum PhotoQueryMatch: String, CaseIterable, Codable, Identifiable {
    case all = "All rules"
    case any = "Any rule"
    public var id: Self { self }
}

public enum PhotoQueryOperator: String, CaseIterable, Codable, Identifiable {
    case contains = "contains"
    case excludes = "does not contain"
    case inBranch = "is in branch"
    case equals = "is"
    case differs = "is not"
    case minimum = "is at least"
    case maximum = "is at most"
    case since = "is on or after"
    case until = "is on or before"
    public var id: Self { self }
}

public enum PhotoQueryField: String, CaseIterable, Codable, Identifiable {
    case filename = "Filename"
    case caption = "Caption"
    case keyword = "Keyword"
    case keywordPath = "Keyword path"
    case iptcTitle = "IPTC Title"
    case iptcCreator = "IPTC Creator"
    case iptcCopyright = "IPTC Copyright"
    case iptcCredit = "IPTC Credit"
    case camera = "Camera"
    case format = "File extension"
    case captured = "Capture date"
    case imported = "Import date"
    case rating = "Rating"
    case flag = "Flag"
    case colorLabel = "Color label"
    case storage = "Original storage"
    case availability = "Original availability"
    case adjusted = "Adjustments"
    public var id: Self { self }

    var iptcField: IPTCField? {
        switch self {
        case .iptcTitle: return .title
        case .iptcCreator: return .creator
        case .iptcCopyright: return .copyright
        case .iptcCredit: return .credit
        default: return nil
        }
    }

    public var operators: [PhotoQueryOperator] {
        switch self {
        case .filename, .caption, .keyword, .camera, .iptcTitle, .iptcCreator, .iptcCopyright, .iptcCredit:
            return [.contains, .excludes, .equals, .differs]
        case .keywordPath: return [.equals, .inBranch, .differs]
        case .format, .colorLabel: return [.equals, .differs]
        case .captured, .imported: return [.since, .until, .equals, .differs]
        case .rating: return [.minimum, .maximum, .equals, .differs]
        case .flag, .storage, .availability, .adjusted: return [.equals]
        }
    }
}

public struct PhotoQueryCriterion: Codable, Equatable, Identifiable {
    public var id = UUID()
    public var field: PhotoQueryField
    public var comparison: PhotoQueryOperator
    public var value: String
    public var keywordPath: KeywordPath?

    public init(field: PhotoQueryField = .filename, comparison: PhotoQueryOperator = .contains, value: String = "",
                keywordPath: KeywordPath? = nil) {
        self.field = field
        self.comparison = comparison
        self.value = value
        self.keywordPath = keywordPath
    }

    private var term: String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isValid: Bool {
        guard field.operators.contains(comparison) else { return false }
        if field == .keywordPath { return keywordPath != nil }
        guard !term.isEmpty else { return false }
        switch field {
        case .captured, .imported: return Self.dayNumber(term, separator: "-") != nil
        case .format: return !Self.normalizedExtension(term).isEmpty
        case .colorLabel: return term == "0" || Int(term).flatMap(PhotoColorLabel.init(rawValue:)) != nil
        case .rating: return Int(term).map { (RatingRules.rejected...RatingRules.maximum).contains($0) } ?? false
        case .flag, .storage, .availability, .adjusted: return term == "true" || term == "false"
        default: return true
        }
    }

    func includes(_ photo: Photo, originalAvailable: () -> Bool?) -> Bool {
        guard field.operators.contains(comparison), field == .keywordPath || !term.isEmpty else { return false }
        switch field {
        case .filename: return matchesText([photo.displayName, photo.originalName, photo.sourceName ?? photo.originalName])
        case .caption: return matchesText([photo.caption])
        case .iptcTitle, .iptcCreator, .iptcCopyright, .iptcCredit:
            return matchesText(field.iptcField.flatMap { photo.iptc?[$0] } ?? [])
        case .keyword: return matchesText(photo.keywordNames)
        case .keywordPath:
            guard let keywordPath else { return false }
            let paths = photo.keywordPaths ?? []
            if comparison == .inBranch { return paths.contains { $0.isWithin(keywordPath) } }
            let found = paths.contains(keywordPath)
            return comparison == .equals ? found : !found
        case .camera: return matchesText([photo.camera])
        case .format:
            let extensionValue = Self.normalizedExtension((photo.filename as NSString).pathExtension)
            let expected = Self.normalizedExtension(term)
            guard !expected.isEmpty else { return false }
            return comparison == .equals ? extensionValue == expected : extensionValue != expected
        case .captured:
            return matchesDay(Self.dayNumber(String(photo.captureDate.prefix(10)), separator: ":"))
        case .imported:
            let components = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day], from: photo.importedAt)
            guard let year = components.year, let month = components.month, let day = components.day else { return false }
            return matchesDay(year * 10000 + month * 100 + day)
        case .rating:
            guard let rating = Int(term), (RatingRules.rejected...RatingRules.maximum).contains(rating) else { return false }
            switch comparison {
            case .minimum: return photo.rating >= rating
            case .maximum: return photo.rating <= rating
            case .equals: return photo.rating == rating
            case .differs: return photo.rating != rating
            default: return false
            }
        case .flag: return matchesBool(photo.flagged)
        case .colorLabel:
            guard isValid else { return false }
            let found = (photo.colorLabel?.rawValue ?? 0) == Int(term)
            return comparison == .equals ? found : !found
        case .storage: return matchesBool(photo.referencedPath != nil)
        case .availability: return originalAvailable().map(matchesBool) ?? false
        case .adjusted: return matchesBool(photo.adjustments != Adjustments())
        }
    }

    private func matchesBool(_ actual: Bool) -> Bool {
        term == (actual ? "true" : "false")
    }

    private func matchesText(_ values: [String]) -> Bool {
        let matchingOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        switch comparison {
        case .contains, .excludes:
            let found = values.contains { $0.range(of: term, options: matchingOptions) != nil }
            return comparison == .contains ? found : !found
        case .equals, .differs:
            let found = values.contains { $0.compare(term, options: matchingOptions) == .orderedSame }
            return comparison == .equals ? found : !found
        default: return false
        }
    }

    private func matchesDay(_ actual: Int?) -> Bool {
        guard let actual, let expected = Self.dayNumber(term, separator: "-") else { return false }
        switch comparison {
        case .since: return actual >= expected
        case .until: return actual <= expected
        case .equals: return actual == expected
        case .differs: return actual != expected
        default: return false
        }
    }

    static func dayNumber(_ string: String, separator: Character) -> Int? {
        let parts = string.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...9999).contains(year), (1...12).contains(month), day > 0 else { return nil }
        let leapYear = year.isMultiple(of: 4) && (!year.isMultiple(of: 100) || year.isMultiple(of: 400))
        let lengths = [31, leapYear ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= lengths[month - 1] else { return nil }
        return year * 10000 + month * 100 + day
    }

    private static func normalizedExtension(_ string: String) -> String {
        let extensionValue = string.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        switch extensionValue {
        case "jpeg": return "jpg"
        case "tiff": return "tif"
        default: return extensionValue
        }
    }
}

public struct PhotoQuery: Codable, Equatable {
    public var match = PhotoQueryMatch.all
    public var criteria: [PhotoQueryCriterion] = []
    public init() {}

    public func includes(_ photo: Photo, originalAvailable: () -> Bool? = { nil }) -> Bool {
        if criteria.isEmpty { return true }
        switch match {
        case .all: return criteria.allSatisfy { $0.includes(photo, originalAvailable: originalAvailable) }
        case .any: return criteria.contains { $0.includes(photo, originalAvailable: originalAvailable) }
        }
    }
}
