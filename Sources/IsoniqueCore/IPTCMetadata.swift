import Foundation
import ImageIO

public enum IPTCField: String, CaseIterable, Codable, Identifiable, Sendable {
    case title, creator, copyright, credit
    public var id: Self { self }

    public var title: String {
        switch self {
        case .title: return String(localized: "Title")
        case .creator: return String(localized: "Creator")
        case .copyright: return String(localized: "Copyright")
        case .credit: return String(localized: "Credit")
        }
    }

    public func values(from text: String) -> [String] {
        if self == .creator {
            return text.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
        return text.isEmpty ? [] : [text]
    }

    fileprivate var imageIOKey: String {
        switch self {
        case .title: return kCGImagePropertyIPTCObjectName as String
        case .creator: return kCGImagePropertyIPTCByline as String
        case .copyright: return kCGImagePropertyIPTCCopyrightNotice as String
        case .credit: return kCGImagePropertyIPTCCredit as String
        }
    }
}

public struct IPTCMetadata: Codable, Equatable, Sendable {
    public var title: String?
    public var creators: [String]?
    public var copyright: String?
    public var credit: String?

    public init(title: String? = nil, creators: [String]? = nil, copyright: String? = nil, credit: String? = nil) {
        self.title = title
        self.creators = creators
        self.copyright = copyright
        self.credit = credit
    }

    /// A missing field inherits the original metadata. An empty value is an explicit clear.
    public subscript(field: IPTCField) -> [String]? {
        get {
            switch field {
            case .title: return title.map(field.values(from:))
            case .creator: return creators
            case .copyright: return copyright.map(field.values(from:))
            case .credit: return credit.map(field.values(from:))
            }
        }
        set {
            switch field {
            case .title: title = newValue.map { $0.first ?? "" }
            case .creator: creators = newValue
            case .copyright: copyright = newValue.map { $0.first ?? "" }
            case .credit: credit = newValue.map { $0.first ?? "" }
            }
        }
    }

    public var isEmpty: Bool { title == nil && creators == nil && copyright == nil && credit == nil }

    func overriding(_ base: Self) -> Self {
        var result = base
        for field in IPTCField.allCases {
            if let values = self[field] { result[field] = values }
        }
        return result
    }

    init(embedded properties: [String: Any], xmp: CGImageMetadata?) {
        self.init()
        for field in IPTCField.allCases {
            let value = properties[field.imageIOKey]
            if field == .creator, let values = value as? [String] { self[field] = values }
            else if let value = value as? String { self[field] = field == .creator ? [value] : field.values(from: value) }
        }
        if let xmp { self = XMPMetadata.iptc(from: xmp).overriding(self) }
    }

    func writing(to properties: inout [String: Any]) {
        for field in IPTCField.allCases {
            guard let values = self[field] else { continue }
            if field == .creator {
                properties[field.imageIOKey] = values.isEmpty ? nil : values
            } else {
                properties[field.imageIOKey] = values.first
            }
        }
    }
}

public struct IPTCFieldEdit: Codable, Equatable, Identifiable {
    public let field: IPTCField
    public let values: [String]?
    public var id: IPTCField { field }

    public init(field: IPTCField, values: [String]?) {
        self.field = field
        self.values = values
    }

    public var text: String? { values?.joined(separator: "\n") }
}

extension Photo {
    public var hasUncataloguedIPTC: Bool { IPTCField.allCases.contains { iptc?[$0] == nil } }

    @discardableResult
    public mutating func applyIPTC(_ changes: [IPTCFieldEdit]) -> [IPTCFieldEdit] {
        var metadata = iptc ?? IPTCMetadata()
        let previous = changes.map { change in
            let old = IPTCFieldEdit(field: change.field, values: metadata[change.field])
            metadata[change.field] = change.values
            return old
        }
        iptc = metadata.isEmpty ? nil : metadata
        return previous
    }
}
