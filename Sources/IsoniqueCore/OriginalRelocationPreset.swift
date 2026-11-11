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
    private let filename: FilenameTemplate
    private let subfolders: [FilenameTemplate]

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
        do {
            self.filename = try FilenameTemplate(filename)
            self.subfolders = try folders.map { try FilenameTemplate($0, folder: true) }
        } catch let error as FilenameTemplateError {
            throw OriginalRelocationTemplateError.invalid(error.reason)
        }
    }

    func paths(photo: Photo, project: String?, index: Int, destination: URL)
        throws -> (filename: String, folders: [String]) {
        let ext = (photo.filename as NSString).pathExtension
        let name = filename.render(for: photo, project: project, index: index) + (ext.isEmpty ? "" : "." + ext)
        let folders = subfolders.map { $0.render(for: photo, project: project, index: index) }
        let relative = (folders + [name]).joined(separator: "/")
        guard FilenameTemplate.isSafeComponent(name),
              folders.allSatisfy({ FilenameTemplate.isSafeComponent($0, folder: true) }),
              destination.appendingPathComponent(relative).path.utf8.count < Int(PATH_MAX) else {
            throw OriginalRelocationTemplateError.unsafeExpansion(photo.originalName)
        }
        return (name, folders)
    }
}
