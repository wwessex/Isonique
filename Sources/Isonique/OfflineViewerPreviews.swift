import CryptoKit
import ImageIO
import IsoniqueCore
import SwiftUI
import UniformTypeIdentifiers

actor OfflineViewerPreviews {
    static let maximumDimension: CGFloat = 2400
    private static let maximumEntrySize = 32 * 1024 * 1024
    private static let formatVersion = 1

    private struct Source: Codable, Equatable {
        let fingerprint: String
        let path: String
        let adjustments: Adjustments
    }

    private struct Entry: Codable {
        let version: Int
        let source: Source
        let png: Data
    }

    private let directory: URL?
    private let byteLimit: Int
    private let entryLimit: Int
    private var savedSources: [URL: (source: Source, stamp: OriginalFileStamp)] = [:]
    private var pendingSaves: [URL: UUID] = [:]

    init(directory: URL? = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("Isonique/ViewerPreviews", isDirectory: true),
         byteLimit: Int = 512 * 1024 * 1024, entryLimit: Int = 2000) {
        self.directory = directory
        self.byteLimit = max(0, byteLimit)
        self.entryLimit = max(0, entryLimit)
    }

    func save(_ image: CGImage, of photo: Photo, in library: URL, original: URL, stamp: OriginalFileStamp) async {
        guard !Task.isCancelled, byteLimit > 0, entryLimit > 0,
              max(image.width, image.height) <= Int(Self.maximumDimension),
              let source = source(for: photo), let file = file(for: photo, in: library) else { return }
        let saved = savedSources[file]
        let verified = saved?.source.fingerprint == source.fingerprint && saved?.source.path == source.path && saved?.stamp == stamp
        let saveID = UUID()
        pendingSaves[file] = saveID
        defer { if pendingSaves[file] == saveID { pendingSaves[file] = nil } }
        if verified, saved?.source == source, FileManager.default.fileExists(atPath: file.path) {
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            return
        }
        let encode = Task.detached(priority: .utility) {
            guard !Task.isCancelled, OriginalFileStamp(original) == stamp,
                  verified || (try? LibraryRepository.digest(original, checkingCancellation: true)) == source.fingerprint,
                  OriginalFileStamp(original) == stamp, !Task.isCancelled else { return nil as Data? }
            let png = NSMutableData()
            guard let writer = CGImageDestinationCreateWithData(png, UTType.png.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(writer, image, nil)
            guard CGImageDestinationFinalize(writer), !Task.isCancelled else { return nil }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .binary
            return try? encoder.encode(Entry(version: Self.formatVersion, source: source, png: png as Data))
        }
        let data = await withTaskCancellationHandler { await encode.value } onCancel: { encode.cancel() }
        guard !Task.isCancelled, pendingSaves[file] == saveID, OriginalFileStamp(original) == stamp,
              let data, data.count <= min(byteLimit, Self.maximumEntrySize) else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
            savedSources[file] = (source, stamp)
            prune()
        } catch {
            // A cache failure must not interrupt the live Viewer.
        }
    }

    func image(for photo: Photo, in library: URL) -> CGImage? {
        guard !Task.isCancelled, let source = source(for: photo), let file = file(for: photo, in: library),
              let entry = entry(at: file), entry.source == source,
              let decoder = CGImageSourceCreateWithData(entry.png as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(decoder, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              (1...Int(Self.maximumDimension)).contains(width), (1...Int(Self.maximumDimension)).contains(height),
              let image = CGImageSourceCreateImageAtIndex(decoder, 0, nil), !Task.isCancelled else { return nil }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return image
    }

    private func source(for photo: Photo) -> Source? {
        photo.referencedPath.map { Source(fingerprint: photo.sha256, path: $0, adjustments: photo.adjustments) }
    }

    private func file(for photo: Photo, in library: URL) -> URL? {
        guard let directory else { return nil }
        let hash = SHA256.hash(data: Data(library.standardizedFileURL.path.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(hash)-\(photo.id.uuidString).preview")
    }

    private func entry(at file: URL) -> Entry? {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true, values.isSymbolicLink == false,
              let size = values.fileSize, size <= Self.maximumEntrySize,
              let data = try? Data(contentsOf: file),
              let entry = try? PropertyListDecoder().decode(Entry.self, from: data),
              entry.version == Self.formatVersion else { return nil }
        return entry
    }

    private func prune() {
        guard let directory else { return }
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys))) ?? []
        let entries = files.compactMap { file -> (file: URL, size: Int, date: Date)? in
            guard file.pathExtension == "preview", let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, let size = values.fileSize else { return nil }
            return (file, size, values.contentModificationDate ?? .distantPast)
        }.sorted { $0.date < $1.date }
        var bytes = entries.reduce(0) { $0 + $1.size }
        var count = entries.count
        for entry in entries where bytes > byteLimit || count > entryLimit {
            do {
                try FileManager.default.removeItem(at: entry.file)
                savedSources[entry.file] = nil
                bytes -= entry.size
                count -= 1
            } catch { continue }
        }
    }
}

struct OfflinePhotoViewer: View {
    @EnvironmentObject private var model: Workspace
    let photo: Photo
    let library: URL
    @State private var result: (Request, CGImage?)?

    private struct Request: Equatable {
        let library: URL
        let photo: Photo
        let revision: Int
    }

    var body: some View {
        let request = Request(library: library, photo: photo, revision: model.originalStatusRevision)
        Group {
            if let (loaded, image) = result, loaded == request {
                if let image {
                    VStack(spacing: 10) {
                        HStack {
                            Label("Offline Preview", systemImage: "externaldrive.badge.minus").font(.headline)
                            Text(photo.displayName).lineLimit(1).foregroundStyle(.secondary)
                            Spacer()
                            if !model.isViewingTrash {
                                Button("Relink Original…") { model.relinkOriginalPanel(photo) }
                            }
                            Button("Refresh", action: model.refreshOriginalStatus)
                        }
                        Image(image, scale: 1, label: Text("Offline preview of \(photo.displayName)"))
                            .resizable().scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .padding(16)
                } else {
                    MissingOriginalView(photo: photo)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: request) {
            let image = await model.offlineViewerPreviews.image(for: request.photo, in: request.library)
            guard !Task.isCancelled else { return }
            result = (request, image)
        }
    }
}
