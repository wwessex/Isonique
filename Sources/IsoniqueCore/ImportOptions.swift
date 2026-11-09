import Foundation

public enum PairingMode: String, Codable, CaseIterable, Identifiable {
    case separate = "Keep separate", linked = "Link RAW + JPEG", raw = "Prefer RAW", jpeg = "Prefer JPEG"
    case linkedRAW = "Both (Use RAW as Original)", onlyJPEG = "JPEG files only", onlyRAW = "RAW files only"
    public var id: String { rawValue }
    public var title: String { self == .linked ? "Both (Use JPEG as Original)" : rawValue }
    public var linksCompanions: Bool { self == .linked || self == .linkedRAW }
}
public struct ImportOptions: Codable, Equatable {
    public var pairing = PairingMode.linked
    public var storage: OriginalStorage?
    public var createProject: Bool?
    public var prefix = ""
    public var caption = ""
    public var keywords = ""
    public var rating = 0
    public var applyMetadata = false
    public var readSidecars = false
    public init() {}
    public static let rawExtensions: Set<String> = ["dng", "raw", "cr2", "cr3", "crw", "nef", "nrw", "arw", "srf", "sr2", "orf", "raf", "rw2", "pef", "ptx", "rwl", "3fr", "fff", "iiq", "mos", "mrw", "x3f", "erf", "kdc", "dcr", "srw"]
    public static func key(_ url: URL) -> String { url.deletingPathExtension().standardizedFileURL.path.lowercased() }
    public static func isRAW(_ url: URL) -> Bool { rawExtensions.contains(url.pathExtension.lowercased()) }
    public static func isJPEG(_ url: URL) -> Bool { ["jpg", "jpeg"].contains(url.pathExtension.lowercased()) }
    public func files(_ urls: [URL]) -> [URL] {
        let unique = Array(Set(urls)).sorted { $0.path < $1.path }
        switch pairing {
        case .onlyJPEG: return unique.filter(Self.isJPEG)
        case .onlyRAW: return unique.filter(Self.isRAW)
        case .raw:
            let preferred = Set(unique.filter(Self.isRAW).map(Self.key))
            return unique.filter { !Self.isJPEG($0) || !preferred.contains(Self.key($0)) }
        case .jpeg:
            let preferred = Set(unique.filter(Self.isJPEG).map(Self.key))
            return unique.filter { !Self.isRAW($0) || !preferred.contains(Self.key($0)) }
        default: return unique
        }
    }
    public func applying(to source: Photo) -> Photo {
        var photo = source
        let clean = prefix.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        if !clean.isEmpty { photo.originalName = clean + "-" + photo.originalName }
        if applyMetadata { photo.caption = caption; photo.keywords = keywords; photo.rating = RatingRules.clamp(rating) }
        return photo
    }
}
public struct ImportPreset: Codable, Identifiable {
    public var id = UUID()
    public var name: String
    public var options: ImportOptions
    public init(name: String, options: ImportOptions) { self.name = name; self.options = options }
}
public struct EditHistory: Codable {
    public var undo: [Photo] = []
    public var redo: [Photo] = []
    public init() {}
    public mutating func record(_ photo: Photo) { undo.append(photo); undo = Array(undo.suffix(100)); redo.removeAll() }
}
public struct MetadataRecord {
    public var filename: String?
    public var caption: String?
    public var keywords: String?
    public var rating: Int?
    public func applying(to source: Photo) -> Photo {
        var result = source
        if let caption { result.caption = caption }
        if let keywords { result.keywords = keywords }
        if let rating { result.rating = RatingRules.clamp(rating) }
        return result
    }
}
/// Supported XML: XMP sidecars, portable <photos><photo filename="…"> records,
/// and Apple's AlbumData.xml property-list Master Image List. Never follows XML entities.
public final class MetadataXML: NSObject, XMLParserDelegate {
    private var records: [MetadataRecord] = []
    private var current: MetadataRecord?
    private var path: [String] = []
    private var content = ""
    private var keywords: [String] = []
    public static func read(_ url: URL) throws -> [MetadataRecord] {
        let data = try Data(contentsOf: url)
        guard data.count <= 16 * 1024 * 1024 else { throw CocoaError(.fileReadTooLarge) }
        if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           let images = plist["Master Image List"] as? [String: [String: Any]] {
            return images.values.map { item in
                MetadataRecord(filename: (item["ImagePath"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }, caption: item["Comment"] as? String, keywords: nil, rating: (item["Rating"] as? NSNumber)?.intValue)
            }
        }
        let reader = MetadataXML(), parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.delegate = reader
        guard parser.parse(), !reader.records.isEmpty else { throw parser.parserError ?? CocoaError(.fileReadCorruptFile) }
        return reader.records
    }
    public func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        path.append(name); content = ""
        if name == "photo" || name == "rdf:Description" {
            current = MetadataRecord(filename: attributes["filename"])
            keywords = []
            if let value = attributes["xmp:Rating"], let rating = Int(value) { current?.rating = rating }
        }
    }
    public func parser(_ parser: XMLParser, foundCharacters string: String) { content += string }
    public func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if name == "caption" || (name == "rdf:li" && path.contains("dc:description")) { current?.caption = text }
        if name == "keywords" { current?.keywords = text }
        if name == "rdf:li" && path.contains("dc:subject") { keywords.append(text) }
        if name == "dc:subject" { current?.keywords = keywords.joined(separator: ", ") }
        if name == "rating" || name == "xmp:Rating" { current?.rating = Int(text) }
        if name == "photo" || name == "rdf:Description" {
            if let current, current.caption != nil || current.keywords != nil || current.rating != nil { records.append(current) }
            current = nil
        }
        _ = path.popLast(); content = ""
    }
}
