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
    case isPresent = "is present"
    case isMissing = "is missing"
    public var id: Self { self }
    public var needsValue: Bool { self != .isPresent && self != .isMissing }
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
    case exifShutterSpeed = "EXIF Shutter Speed"
    case exifAperture = "EXIF Aperture"
    case exifISO = "EXIF ISO"
    case exifFocalLength = "EXIF Focal Length"
    case exifLens = "EXIF Lens"
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

    var isEXIF: Bool {
        switch self {
        case .exifShutterSpeed, .exifAperture, .exifISO, .exifFocalLength, .exifLens: return true
        default: return false
        }
    }

    public var operators: [PhotoQueryOperator] {
        switch self {
        case .filename, .caption, .keyword, .camera, .iptcTitle, .iptcCreator, .iptcCopyright, .iptcCredit:
            return [.contains, .excludes, .equals, .differs]
        case .exifShutterSpeed, .exifAperture, .exifISO, .exifFocalLength:
            return [.equals, .minimum, .maximum, .differs, .isPresent, .isMissing]
        case .exifLens: return [.contains, .excludes, .equals, .differs, .isPresent, .isMissing]
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
        if !comparison.needsValue { return true }
        if field == .keywordPath { return keywordPath != nil }
        guard !term.isEmpty else { return false }
        switch field {
        case .exifShutterSpeed, .exifAperture, .exifFocalLength: return exifNumber != nil
        case .exifISO: return exifISO != nil
        case .captured, .imported: return Self.dayNumber(term, separator: "-") != nil
        case .format: return !Self.normalizedExtension(term).isEmpty
        case .colorLabel: return term == "0" || Int(term).flatMap(PhotoColorLabel.init(rawValue:)) != nil
        case .rating: return Int(term).map { (RatingRules.rejected...RatingRules.maximum).contains($0) } ?? false
        case .flag, .storage, .availability, .adjusted: return term == "true" || term == "false"
        default: return true
        }
    }

    func includes(_ photo: Photo, originalAvailable: () -> Bool?) -> Bool {
        guard field.operators.contains(comparison),
              !comparison.needsValue || field == .keywordPath || !term.isEmpty else { return false }
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
        case .exifShutterSpeed: return matchesEXIFNumber(photo.cameraEXIF?.exposureSeconds)
        case .exifAperture: return matchesEXIFNumber(photo.cameraEXIF?.fNumber)
        case .exifFocalLength: return matchesEXIFNumber(photo.cameraEXIF?.focalLengthMM)
        case .exifISO:
            return matchesEXIFValue(photo.cameraEXIF?.iso) { actual in
                guard let expected = exifISO else { return false }
                let order: ComparisonResult = actual == expected ? .orderedSame : (actual < expected ? .orderedAscending : .orderedDescending)
                return matchesOrder(order)
            }
        case .exifLens: return matchesEXIFValue(photo.cameraEXIF?.lens) { matchesText([$0]) }
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

    private var exifISO: Int? {
        guard let value = Int(term), value > 0 else { return nil }
        return value
    }

    private var exifNumber: Double? {
        var input = term.lowercased()
        switch field {
        case .exifShutterSpeed:
            if input.hasSuffix("s") { input.removeLast() }
            let parts = input.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2,
               let numerator = Self.positiveDecimal(String(parts[0])),
               let denominator = Self.positiveDecimal(String(parts[1])) {
                let seconds = numerator / denominator
                return seconds.isFinite && seconds > 0 ? seconds : nil
            }
        case .exifAperture:
            if input.hasPrefix("f/") || input.hasPrefix("ƒ/") { input.removeFirst(2) }
        case .exifFocalLength:
            if input.hasSuffix("mm") { input.removeLast(2) }
        default: return nil
        }
        return Self.positiveDecimal(input)
    }

    private static func positiveDecimal(_ text: String) -> Double? {
        let decimal = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard decimal.allSatisfy({ "0123456789.".contains($0) }),
              let value = Double(decimal), value.isFinite, value > 0 else { return nil }
        return value
    }

    private func matchesEXIFValue<Value>(_ actual: Value?, match: (Value) -> Bool) -> Bool {
        if comparison == .isMissing { return actual == nil }
        if comparison == .isPresent { return actual != nil }
        return actual.map(match) ?? false
    }

    private func matchesEXIFNumber(_ value: Double?) -> Bool {
        matchesEXIFValue(value) { actual in
            guard let expected = exifNumber else { return false }
            // ImageIO can return a float32 approximation of the recorded rational.
            let same = abs(actual - expected) <= max(actual, expected) * 0.000001
            let order: ComparisonResult = same ? .orderedSame : (actual < expected ? .orderedAscending : .orderedDescending)
            return matchesOrder(order)
        }
    }

    private func matchesOrder(_ order: ComparisonResult) -> Bool {
        switch comparison {
        case .equals: return order == .orderedSame
        case .differs: return order != .orderedSame
        case .minimum: return order != .orderedAscending
        case .maximum: return order != .orderedDescending
        default: return false
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
