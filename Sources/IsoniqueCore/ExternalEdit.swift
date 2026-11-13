import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ExternalEditError: LocalizedError, Equatable {
    case sourceChanged
    case returnMissing
    case returnUnchanged
    case returnIsNotTIFF
    case duplicateReturn

    public var errorDescription: String? {
        switch self {
        case .sourceChanged:
            return "The source photo changed while it was open in the external editor. Start the external edit again."
        case .returnMissing:
            return "The external editor return file is missing. Save the TIFF in the editor, then try again."
        case .returnUnchanged:
            return "The external editor has not saved any changes to the TIFF yet."
        case .returnIsNotTIFF:
            return "The external editor return must remain a readable TIFF file."
        case .duplicateReturn:
            return "The returned TIFF is already in this library."
        }
    }
}

public struct ExternalEditHandoff: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let sourcePhotoID: UUID
    public let fileURL: URL
    let initialDigest: String
    let sourceDigest: String

    init(id: UUID = UUID(), sourcePhotoID: UUID, fileURL: URL,
         initialDigest: String, sourceDigest: String) {
        self.id = id
        self.sourcePhotoID = sourcePhotoID
        self.fileURL = fileURL
        self.initialDigest = initialDigest
        self.sourceDigest = sourceDigest
    }
}

public struct ExternalEditResult {
    public let library: Library
    public let photo: Photo
}

public extension LibraryRepository {
    /// Renders the selected version into an isolated TIFF that an external editor may replace in place.
    func beginExternalEdit(_ photo: Photo) throws -> ExternalEditHandoff {
        let original = try availableOriginalURL(photo)
        let sourceDigest = try Self.digest(original)
        guard sourceDigest == photo.sha256 else { throw LibraryError.integrity(photo.originalName) }

        let id = UUID()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IsoniqueExternalEdit-\(id.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let filename = photo.exportBaseName.isEmpty ? "External Edit.tiff" : "\(photo.exportBaseName) — External Edit.tiff"
        let returnURL = directory.appendingPathComponent(filename)
        do {
            var options = ExportOptions()
            options.format = .tiff
            options.tiffCompression = .zip
            options.exif = true
            options.iptc = true
            options.gps = true
            try Renderer.export(photo, repository: self, to: returnURL, options: options)
            let initialDigest = try Self.digest(returnURL)
            return ExternalEditHandoff(id: id, sourcePhotoID: photo.id, fileURL: returnURL,
                                       initialDigest: initialDigest, sourceDigest: sourceDigest)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    /// Removes only the isolated directory created for this handoff.
    func cancelExternalEdit(_ handoff: ExternalEditHandoff) throws {
        let directory = try externalEditDirectory(for: handoff)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// Imports a changed TIFF as an independently managed derivative, leaving the source original untouched.
    func finishExternalEdit(_ handoff: ExternalEditHandoff, in library: Library) throws -> ExternalEditResult {
        _ = try externalEditDirectory(for: handoff)
        guard let source = library.photos.first(where: { $0.id == handoff.sourcePhotoID && $0.trashedAt == nil }) else {
            throw ExternalEditError.sourceChanged
        }
        guard source.sha256 == handoff.sourceDigest,
              try Self.digest(availableOriginalURL(source)) == handoff.sourceDigest else {
            throw ExternalEditError.sourceChanged
        }
        let values = try? handoff.fileURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values?.isRegularFile == true, values?.isSymbolicLink != true else {
            throw ExternalEditError.returnMissing
        }
        let returnedDigest = try Self.digest(handoff.fileURL)
        guard returnedDigest != handoff.initialDigest else { throw ExternalEditError.returnUnchanged }
        guard !library.photos.contains(where: { $0.sha256 == returnedDigest }) else {
            throw ExternalEditError.duplicateReturn
        }
        guard let imageSource = CGImageSourceCreateWithURL(handoff.fileURL as CFURL, nil),
              CGImageSourceGetCount(imageSource) > 0,
              CGImageSourceGetType(imageSource) as String? == UTType.tiff.identifier,
              let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else {
            throw ExternalEditError.returnIsNotTIFF
        }

        let managedFilename = UUID().uuidString + ".tiff"
        let installed = try managedOriginalURL(managedFilename)
        var copied = false
        defer { if copied { try? FileManager.default.removeItem(at: installed) } }
        try FileManager.default.copyItem(at: handoff.fileURL, to: installed)
        copied = true
        guard try Self.digest(installed) == returnedDigest else { throw LibraryError.integrity(handoff.fileURL.lastPathComponent) }

        var derivative = source
        derivative.id = UUID()
        derivative.trashedAt = nil
        derivative.sharedOriginalID = nil
        derivative.versionName = externalEditName(for: source, in: library)
        derivative.referencedPath = nil
        derivative.versions = nil
        derivative.pairID = nil
        derivative.filename = managedFilename
        derivative.originalName = derivative.versionName! + ".tiff"
        derivative.sourceName = source.sourceName ?? source.originalName
        derivative.importedAt = Date()
        derivative.width = width
        derivative.height = height
        derivative.sha256 = returnedDigest
        derivative.people = nil
        derivative.adjustments = Adjustments()

        var draft = library
        draft.version = max(draft.version, 3)
        draft.photos.append(derivative)
        let saved = try save(draft)
        copied = false
        try? cancelExternalEdit(handoff)
        return ExternalEditResult(library: saved, photo: derivative)
    }

    private func externalEditDirectory(for handoff: ExternalEditHandoff) throws -> URL {
        let temporary = FileManager.default.temporaryDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let file = handoff.fileURL.standardizedFileURL.resolvingSymlinksInPath()
        let directory = file.deletingLastPathComponent()
        guard directory.deletingLastPathComponent() == temporary,
              directory.lastPathComponent == "IsoniqueExternalEdit-\(handoff.id.uuidString)",
              file.deletingLastPathComponent() == directory else {
            throw LibraryError.unsafePath
        }
        return directory
    }

    private func externalEditName(for source: Photo, in library: Library) -> String {
        let stem = (source.displayName as NSString).deletingPathExtension
        let base = "\(stem) — External Edit"
        let existing = Set(library.photos.map(\.displayName))
        if !existing.contains(base) { return base }
        var number = 2
        while existing.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }
}
