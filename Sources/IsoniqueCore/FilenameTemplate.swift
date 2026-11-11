import Foundation

struct FilenameTemplateError: LocalizedError {
    let reason: String
    var errorDescription: String? { reason }
}

struct FilenameTemplate {
    static let maximumComponentBytes = 255

    private enum Token: String {
        case original, catalogue, version, project, year, month, day, sequence
    }

    private enum Part {
        case literal(String)
        case token(Token)
    }

    private let parts: [Part]

    init(_ component: String, folder: Bool = false, allowsVersion: Bool = false) throws {
        var parts: [Part] = []
        var remaining = component[...]
        while let opening = remaining.firstIndex(of: "{") {
            let literal = remaining[..<opening]
            let after = remaining[remaining.index(after: opening)...]
            guard !literal.contains("}"), let closing = after.firstIndex(of: "}") else {
                throw FilenameTemplateError(reason: "Enclose each token in matching braces, such as {project}.")
            }
            let identifier = String(after[..<closing])
            guard let token = Token(rawValue: identifier), allowsVersion || token != .version else {
                throw FilenameTemplateError(reason: "Unknown naming token {\(identifier)}.")
            }
            parts.append(.literal(String(literal)))
            parts.append(.token(token))
            remaining = after[after.index(after: closing)...]
        }
        guard !remaining.contains("}") else {
            throw FilenameTemplateError(reason: "Enclose each token in matching braces, such as {project}.")
        }
        parts.append(.literal(String(remaining)))
        self.parts = parts
        guard Self.isSafeComponent(render { _ in "Token" }, folder: folder) else {
            let label = folder ? "Subfolders" : "Filenames"
            throw FilenameTemplateError(
                reason: "\(label) must use nonempty names. Avoid leading dots or ~, path separators inside names, and control characters.")
        }
    }

    func render(for photo: Photo, project: String?, index: Int) -> String {
        let date = PhotoQueryCriterion.dayNumber(String(photo.captureDate.prefix(10)), separator: ":")
        return render { token in
            switch token {
            case .original:
                return Self.safeMetadata(((photo.sourceName ?? photo.originalName) as NSString).deletingPathExtension,
                                         fallback: "Original")
            case .catalogue:
                return Self.safeMetadata((photo.originalName as NSString).deletingPathExtension, fallback: "Original")
            case .version:
                return Self.safeMetadata(photo.exportBaseName, fallback: "Photo")
            case .project:
                return Self.safeMetadata(project ?? "", fallback: "Unassigned")
            case .year: return date.map { String(format: "%04d", $0 / 10000) } ?? "Unknown"
            case .month: return date.map { String(format: "%02d", $0 / 100 % 100) } ?? "Unknown"
            case .day: return date.map { String(format: "%02d", $0 % 100) } ?? "Unknown"
            case .sequence: return String(format: "%04d", index + 1)
            }
        }
    }

    private func render(_ value: (Token) -> String) -> String {
        parts.map {
            switch $0 {
            case .literal(let text): return text
            case .token(let token): return value(token)
            }
        }.joined()
    }

    private static let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))

    static func isSafeComponent(_ name: String, folder: Bool = false) -> Bool {
        guard !name.isEmpty, name.utf8.count <= maximumComponentBytes, !name.hasPrefix("."), !name.hasPrefix("~"),
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
        let result = prefixFitting(safe, utf8Limit: 120).trimmingCharacters(in: trim)
        return result.isEmpty ? fallback : result
    }

    static func prefixFitting(_ value: String, utf8Limit: Int) -> String {
        if value.utf8.count <= utf8Limit { return value }
        var result = ""
        var size = 0
        for character in value {
            let bytes = String(character).utf8.count
            guard size + bytes <= utf8Limit else { break }
            result.append(character)
            size += bytes
        }
        return result
    }
}
