import Darwin
import Foundation

public extension BatchExport {
    struct Plan {
        public struct Entry: Identifiable {
            public let photo: Photo
            public let filename: String
            public let sidecarFilename: String?

            public var id: UUID { photo.id }
        }

        public let entries: [Entry]
        let options: ExportOptions

        public func write(to folder: URL, repository: LibraryRepository, didExport: () -> Void = {}) throws {
            let target = folder.standardizedFileURL.resolvingSymlinksInPath()
            for entry in entries {
                for name in [entry.filename, entry.sidecarFilename].compactMap({ $0 }) {
                    guard target.appendingPathComponent(name).path.utf8.count < Int(PATH_MAX) else {
                        throw NamingError.pathTooLong(name)
                    }
                }
            }
            try Task.checkCancellation()
            try BatchExport.prepareDirectory(target, repository: repository)
            for entry in entries {
                try Task.checkCancellation()
                try Renderer.export(entry.photo, repository: repository,
                                    to: target.appendingPathComponent(entry.filename), options: options)
                didExport()
            }
        }
    }

    static func plan(photos: [Photo], projects: [Collection], options: ExportOptions) throws -> Plan {
        let template: FilenameTemplate?
        if let pattern = options.filenameTemplate {
            guard pattern.utf8.count <= 512 else {
                throw FilenameTemplateError(reason: "Use up to 512 UTF-8 bytes in the filename template.")
            }
            template = try FilenameTemplate(pattern, allowsVersion: true)
        } else {
            template = nil
        }

        let projectNames = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        var usedNames = Set<String>()
        var nextSuffix: [String: Int] = [:]
        let entries = try photos.enumerated().map { index, photo in
            let project = photo.projectID.flatMap { projectNames[$0] }
            let base = template?.render(for: photo, project: project, index: index)
                ?? "\(index + 1)-\(photo.exportBaseName)"
            let ext = options.format == .original ? (photo.filename as NSString).pathExtension : options.format.suffix
            let extensionSuffix = ext.isEmpty ? "" : "." + ext
            let includeSidecar = options.xmpSidecar == true
            let requestedName = includeSidecar ? base + ".xmp" : base + extensionSuffix
            let requestedKey = managedFilenameKey(requestedName)
            let extensionBytes = max(extensionSuffix.utf8.count, includeSidecar ? ".xmp".utf8.count : 0)
            var stem = base
            while true {
                let filename = stem + extensionSuffix
                let sidecar = includeSidecar ? stem + ".xmp" : nil
                guard FilenameTemplate.isSafeComponent(filename), (filename as NSString).pathExtension == ext,
                      sidecar.map({ FilenameTemplate.isSafeComponent($0) && ext.lowercased() != "xmp" }) != false else {
                    throw NamingError.invalidFilename(photo.displayName)
                }
                let keys = [filename, sidecar].compactMap { $0 }.map(managedFilenameKey)
                if usedNames.isDisjoint(with: keys) {
                    usedNames.formUnion(keys)
                    return Plan.Entry(photo: photo, filename: filename, sidecarFilename: sidecar)
                }
                let number = nextSuffix[requestedKey, default: 2]
                nextSuffix[requestedKey] = number + 1
                let suffix = "-\(number)"
                let limit = FilenameTemplate.maximumComponentBytes - extensionBytes - suffix.utf8.count
                stem = FilenameTemplate.prefixFitting(base, utf8Limit: limit) + suffix
            }
        }
        return Plan(entries: entries, options: options)
    }
}

private extension BatchExport {
    enum NamingError: LocalizedError {
        case invalidFilename(String)
        case pathTooLong(String)

        var errorDescription: String? {
            switch self {
            case .invalidFilename(let photo):
                return "The template produces an unsafe or overly long filename for “\(photo)”. Shorten or change the template."
            case .pathTooLong(let name):
                return "The destination path for “\(name)” is too long. Choose a shorter destination folder."
            }
        }
    }
}
