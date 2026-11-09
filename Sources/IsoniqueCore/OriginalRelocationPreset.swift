import Darwin
import Foundation

public struct OriginalRelocationPreset: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let name: String
    public let filenamePattern: String
    public let subfolderPattern: String

    public init(id: UUID = UUID(), name: String, filenamePattern: String, subfolderPattern: String) throws {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.filenamePattern = filenamePattern
        self.subfolderPattern = subfolderPattern
        _ = try compile()
    }

    public func validate() throws { _ = try compile() }

    func compile() throws -> RelocationPathTemplate {
        guard !name.isEmpty, name.count <= 64, name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw OriginalRelocationTemplateError.invalid("Enter a preset name of 1–64 characters.")
        }
        return try RelocationPathTemplate(filename: filenamePattern, subfolders: subfolderPattern)
    }
}

public enum OriginalRelocationTemplateError: LocalizedError {
    case invalid(String)
    case unsafeExpansion(String)

    public var errorDescription: String? {
        switch self {
        case .invalid(let reason): return reason
        case .unsafeExpansion(let photo): return "The preset produces an unsafe or overly long path for “\(photo)”. Shorten or change the template."
        }
    }
}

struct RelocationPathTemplate {
    private enum Token: String {
        case original, catalogue, project, year, month, day, sequence
    }

    private enum Part {
        case literal(String)
        case token(Token)
    }

    private let filename: [Part]
    private let subfolders: [[Part]]

    init(filename: String, subfolders: String) throws {
        guard filename.utf8.count <= 512, subfolders.utf8.count <= 512 else {
            throw OriginalRelocationTemplateError.invalid("Each template can use up to 512 UTF-8 bytes.")
        }
        guard !filename.contains("/") else {
            throw OriginalRelocationTemplateError.invalid("Use a single filename template. Put folder names in the subfolder template.")
        }
        let folders = subfolders.isEmpty ? [] : subfolders.components(separatedBy: "/")
        guard folders.count <= 8 else {
            throw OriginalRelocationTemplateError.invalid("Use up to eight levels of subfolders.")
        }
        self.filename = try Self.parse(filename, folder: false)
        self.subfolders = try folders.map { try Self.parse($0, folder: true) }
    }

    private static func parse(_ component: String, folder: Bool) throws -> [Part] {
        var parts: [Part] = []
        var remaining = component[...]
        while let opening = remaining.firstIndex(of: "{") {
            let literal = remaining[..<opening]
            let after = remaining[remaining.index(after: opening)...]
            guard !literal.contains("}"), let closing = after.firstIndex(of: "}") else {
                throw OriginalRelocationTemplateError.invalid("Enclose each token in matching braces, such as {project}.")
            }
            let identifier = String(after[..<closing])
            guard let token = Token(rawValue: identifier) else {
                throw OriginalRelocationTemplateError.invalid("Unknown relocation token: {\(identifier)}.")
            }
            parts.append(.literal(String(literal)))
            parts.append(.token(token))
            remaining = after[after.index(after: closing)...]
        }
        guard !remaining.contains("}") else {
            throw OriginalRelocationTemplateError.invalid("Enclose each token in matching braces, such as {project}.")
        }
        parts.append(.literal(String(remaining)))
        let sample = render(parts) { _ in "Token" }
        guard safeComponent(sample, folder: folder) else {
            let label = folder ? "Subfolders" : "Filenames"
            throw OriginalRelocationTemplateError.invalid(
                "\(label) must use nonempty names. Avoid leading dots or ~, path separators inside names, and control characters.")
        }
        return parts
    }

    func paths(photo: Photo, project: String?, index: Int, destination: URL)
        throws -> (filename: String, folders: [String]) {
        let date = PhotoQueryCriterion.dayNumber(String(photo.captureDate.prefix(10)), separator: ":")
        let original = Self.safeMetadata(((photo.sourceName ?? photo.originalName) as NSString).deletingPathExtension, fallback: "Original")
        let catalogue = Self.safeMetadata((photo.originalName as NSString).deletingPathExtension, fallback: "Original")
        let projectName = Self.safeMetadata(project ?? "", fallback: "Unassigned")
        func value(_ token: Token) -> String {
            switch token {
            case .original: return original
            case .catalogue: return catalogue
            case .project: return projectName
            case .year: return date.map { String(format: "%04d", $0 / 10000) } ?? "Unknown"
            case .month: return date.map { String(format: "%02d", $0 / 100 % 100) } ?? "Unknown"
            case .day: return date.map { String(format: "%02d", $0 % 100) } ?? "Unknown"
            case .sequence: return String(format: "%04d", index + 1)
            }
        }
        let ext = (photo.filename as NSString).pathExtension
        let name = Self.render(filename, value: value) + (ext.isEmpty ? "" : "." + ext)
        let folders = subfolders.map { Self.render($0, value: value) }
        let relative = (folders + [name]).joined(separator: "/")
        guard Self.safeComponent(name, folder: false), folders.allSatisfy({ Self.safeComponent($0, folder: true) }),
              destination.appendingPathComponent(relative).path.utf8.count < Int(PATH_MAX) else {
            throw OriginalRelocationTemplateError.unsafeExpansion(photo.originalName)
        }
        return (name, folders)
    }

    private static func render(_ parts: [Part], value: (Token) -> String) -> String {
        parts.map {
            switch $0 {
            case .literal(let text): return text
            case .token(let token): return value(token)
            }
        }.joined()
    }

    private static let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))

    private static func safeComponent(_ name: String, folder: Bool) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 255, !name.hasPrefix("."), !name.hasPrefix("~"),
              name.trimmingCharacters(in: .whitespacesAndNewlines) == name,
              name.rangeOfCharacter(from: forbidden) == nil else { return false }
        if folder {
            let root = URL(fileURLWithPath: "/", isDirectory: true)
            return (try? LibraryRepository.validateRoot(root.appendingPathComponent(name, isDirectory: true))) != nil
        }
        return true
    }

    private static func safeMetadata(_ value: String, fallback: String) -> String {
        let trim = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".~"))
        let safe = value.components(separatedBy: forbidden).joined(separator: "-").trimmingCharacters(in: trim)
        var result = ""
        var size = 0
        for character in safe {
            let bytes = String(character).utf8.count
            guard size + bytes <= 120 else { break }
            result.append(character)
            size += bytes
        }
        result = result.trimmingCharacters(in: trim)
        return result.isEmpty ? fallback : result
    }
}
