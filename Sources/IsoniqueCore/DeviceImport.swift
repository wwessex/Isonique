import Darwin
import Foundation

/// A mounted card or mass-storage camera with a standard DCIM directory.
public struct MemoryCardSource: Identifiable, Hashable, Sendable {
    public let volume: URL
    public let folder: URL
    public let name: String
    private let volumeUUID: String?
    public var id: URL { volume }

    public init?(volume: URL) {
        guard volume.isFileURL, let rootPath = Self.canonicalPath(volume) else { return nil }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: Array(keys)),
              let dcim = entries.sorted(by: { $0.path < $1.path }).first(where: { child in
                  guard child.lastPathComponent.caseInsensitiveCompare("DCIM") == .orderedSame,
                        let values = try? child.resourceValues(forKeys: keys) else { return false }
                  return values.isDirectory == true && values.isSymbolicLink != true
              }), let dcimPath = Self.canonicalPath(dcim), dcimPath == root.appendingPathComponent(dcim.lastPathComponent).path
              else { return nil }
        let values = try? root.resourceValues(forKeys: [.volumeNameKey, .volumeUUIDStringKey])
        self.volume = root
        folder = URL(fileURLWithPath: dcimPath, isDirectory: true)
        name = values?.volumeName ?? root.lastPathComponent
        volumeUUID = values?.volumeUUIDString
    }

    public static func discover() -> [MemoryCardSource] {
        let keys: [URLResourceKey] = [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsEjectableKey]
        return (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: .skipHiddenVolumes) ?? [])
            .compactMap { url in
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.volumeIsLocal == true,
                      values.volumeIsRemovable == true || values.volumeIsEjectable == true else { return nil }
                return MemoryCardSource(volume: url)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func checkAvailable() throws {
        guard let current = MemoryCardSource(volume: volume), current.folder.path == folder.path,
              volumeUUID == nil || current.volumeUUID == volumeUUID else { throw DeviceImportError.disconnected }
    }

    func photoFiles() -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let entries = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var photos: [URL] = []
        for case let url as URL in entries {
            if Task.isCancelled { break }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { entries.skipDescendants(); continue }
            if values.isRegularFile == true, ImportOptions.imageExtensions.contains(url.pathExtension.lowercased()) {
                photos.append(url)
            }
        }
        return photos
    }

    func validateFile(_ url: URL) throws {
        do {
            guard let path = Self.canonicalPath(url) else { throw CocoaError(.fileReadNoSuchFile) }
            guard path == url.path, path.hasPrefix(folder.path + "/") else { throw LibraryError.unsafePath }
            let values = try url.resourceValues(forKeys: [.volumeUUIDStringKey])
            guard volumeUUID == nil || values.volumeUUIDString == volumeUUID else { throw DeviceImportError.disconnected }
            try LibraryBackup.regularFile(url)
        } catch {
            try checkAvailable()
            throw error
        }
    }

    private static func canonicalPath(_ url: URL) -> String? {
        guard let path = realpath(url.path, nil) else { return nil }
        defer { free(path) }
        return String(cString: path)
    }

}

/// A validated camera catalogue path. It is used for pairing, never as a local filesystem destination.
public struct CameraImportFile: Hashable, Sendable {
    public let components: [String]
    public let byteCount: Int64?
    public var filename: String { components[components.count - 1] }

    public init?(components: [String], byteCount: Int64? = nil) {
        guard (1...32).contains(components.count), components.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.count <= 255 &&
                $0.rangeOfCharacter(from: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))) == nil
        }) else { return nil }
        self.components = components
        self.byteCount = byteCount.flatMap { $0 > 0 ? $0 : nil }
    }

    var logicalURL: URL {
        components.reduce(URL(fileURLWithPath: "/Camera", isDirectory: true)) { $0.appendingPathComponent($1) }
    }

    public var isPhoto: Bool { ImportOptions.imageExtensions.contains(logicalURL.pathExtension.lowercased()) }
    public var isSidecar: Bool { logicalURL.pathExtension.lowercased() == "xmp" }
}

public enum DeviceImportError: LocalizedError {
    case disconnected, timedOut, accessRestricted, noPhotos, incompleteDownload(String), ambiguous(String)

    var stopsImport: Bool {
        switch self {
        case .disconnected, .timedOut, .accessRestricted: return true
        default: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .disconnected: return "The camera or memory card is no longer available. Reconnect it and try again."
        case .timedOut: return "The camera did not respond. Unlock or reconnect it, then try again."
        case .accessRestricted: return "Unlock the camera or device and allow photo transfer, then try again."
        case .noPhotos: return "No supported photographs were found on this device."
        case .incompleteDownload(let name): return "The camera did not deliver a complete copy of \(name)."
        case .ambiguous(let name): return "The camera reported more than one file at \(name); it was skipped."
        }
    }
}
