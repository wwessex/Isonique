import Foundation
import ImageIO

enum XMPMetadata {
    private static let lightroom = "http://ns.adobe.com/lightroom/1.0/"
    private static let dublinCore = "http://purl.org/dc/elements/1.1/"
    private static let photoshop = "http://ns.adobe.com/photoshop/1.0/"
    private static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"

    enum Failure: LocalizedError {
        case invalidHierarchy, unrepresentablePath(String), sidecarExists(String), encoding

        var errorDescription: String? {
            switch self {
            case .invalidHierarchy: return "The XMP sidecar contains an invalid keyword hierarchy."
            case .unrepresentablePath(let path): return "XMP uses | to separate keyword levels. Replace the assignment “\(path)” with a path that uses a different character before exporting a sidecar."
            case .sidecarExists(let name): return "An item named “\(name)” already exists. Choose a different export filename."
            case .encoding: return "Could not encode the XMP sidecar."
            }
        }
    }

    static func read(_ data: Data) throws -> MetadataRecord? {
        guard let metadata = packet(from: data) else { return nil }
        let caption = localizedText(metadata, at: "dc:description")
        let keywords = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:subject" as CFString)
            .flatMap(strings)?.joined(separator: ", ")
        let paths = try keywordPaths(from: metadata)
        let rating = string(metadata, at: "xmp:Rating").flatMap(Int.init)
        var iptc = iptc(from: metadata)
        if iptc.credit == nil, hasEmptyCredit(in: data) { iptc.credit = "" }
        guard caption != nil || keywords != nil || paths != nil || rating != nil || !iptc.isEmpty else { return nil }
        return MetadataRecord(caption: caption, keywords: keywords, rating: rating, keywordPaths: paths,
                              iptc: iptc.isEmpty ? nil : iptc)
    }

    private static func packet(from data: Data) -> CGImageMetadata? {
        if let metadata = CGImageMetadataCreateFromXMPData(data as CFData) { return metadata }

        // The legacy importer also accepted an RDF root without the XMP wrapper.
        guard let document = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]),
              document.dtd == nil, let root = document.rootElement(),
              root.localName == "RDF", root.uri == rdf else { return nil }
        let wrapped = "<x:xmpmeta xmlns:x=\"adobe:ns:meta/\">" + root.xmlString + "</x:xmpmeta>"
        return CGImageMetadataCreateFromXMPData(Data(wrapped.utf8) as CFData)
    }

    private static func hasEmptyCredit(in data: Data) -> Bool {
        // ImageIO drops empty simple text properties. Check the XML so an explicit clear survives reimport.
        guard let document = try? XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever]),
              document.dtd == nil, let root = document.rootElement(),
              let graph = ([root] + (root.children ?? [])).first(where: { $0.localName == "RDF" && $0.uri == rdf })
        else { return false }

        func isEmptyCredit(_ node: XMLNode) -> Bool {
            node.localName == "Credit" && node.uri == photoshop && node.stringValue == ""
        }

        for case let description as XMLElement in graph.children ?? [] {
            if (description.attributes ?? []).contains(where: isEmptyCredit) { return true }
            for case let element as XMLElement in description.children ?? []
                where isEmptyCredit(element) && (element.attributes ?? []).isEmpty {
                if !(element.children ?? []).contains(where: { $0.kind == .element }) { return true }
            }
        }
        return false
    }

    static func keywordPaths(from metadata: CGImageMetadata) throws -> [KeywordPath]? {
        // ImageIO retains the file's prefix for custom namespaces, so identify this property by URI.
        let tags = CGImageMetadataCopyTags(metadata) as? [CGImageMetadataTag] ?? []
        guard let tag = tags.first(where: {
            CGImageMetadataTagCopyNamespace($0) as String? == lightroom
                && CGImageMetadataTagCopyName($0) as String? == "hierarchicalSubject"
        }) else { return nil }
        guard let entries = strings(tag) else { throw Failure.invalidHierarchy }

        var paths: [KeywordPath] = []
        var seen: Set<KeywordPath> = []
        for entry in entries {
            let components = entry.components(separatedBy: "|")
            guard components.allSatisfy(isRepresentableLevel), let path = KeywordPath(components) else { throw Failure.invalidHierarchy }
            if seen.insert(path).inserted { paths.append(path) }
        }
        return paths
    }

    static func iptc(from metadata: CGImageMetadata) -> IPTCMetadata {
        let creators = CGImageMetadataCopyTagWithPath(metadata, nil, "dc:creator" as CFString)
            .flatMap(strings)
        return IPTCMetadata(title: localizedText(metadata, at: "dc:title"),
                            creators: creators,
                            copyright: localizedText(metadata, at: "dc:rights"),
                            credit: string(metadata, at: "photoshop:Credit"))
    }

    static func encode(_ photo: Photo, iptc: IPTCMetadata) throws -> Data {
        let paths = try (photo.keywordPaths ?? []).map { path in
            guard path.components.allSatisfy(isRepresentableLevel) else { throw Failure.unrepresentablePath(path.title) }
            return path.components.joined(separator: "|")
        }
        let metadata = CGImageMetadataCreateMutable()
        guard CGImageMetadataRegisterNamespaceForPrefix(metadata, lightroom as CFString, "lr" as CFString, nil),
              setArray(paths, name: "hierarchicalSubject", prefix: "lr", namespace: lightroom, on: metadata),
              setArray(KeywordList.values(photo.keywords), name: "subject", prefix: "dc", namespace: dublinCore, on: metadata),
              CGImageMetadataSetValueWithPath(metadata, nil, "dc:description[x-default]" as CFString, photo.caption as CFString),
              CGImageMetadataSetValueWithPath(metadata, nil, "xmp:Rating" as CFString, String(RatingRules.clamp(photo.rating)) as CFString)
        else { throw Failure.encoding }
        for (path, value) in [("dc:title[x-default]", iptc.title), ("dc:rights[x-default]", iptc.copyright),
                              ("photoshop:Credit", iptc.credit)] {
            if let value, !CGImageMetadataSetValueWithPath(metadata, nil, path as CFString, value as CFString) {
                throw Failure.encoding
            }
        }
        if let creators = iptc.creators,
           !setArray(creators, name: "creator", prefix: "dc", namespace: dublinCore, type: .arrayOrdered, on: metadata) {
            throw Failure.encoding
        }
        guard let data = CGImageMetadataCreateXMPData(metadata, nil) else { throw Failure.encoding }
        return data as Data
    }

    private static func isRepresentableLevel(_ name: String) -> Bool {
        !name.contains("|") && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func setArray(_ values: [String], name: String, prefix: String, namespace: String,
                                 type: CGImageMetadataType = .arrayUnordered, on metadata: CGMutableImageMetadata) -> Bool {
        guard let tag = CGImageMetadataTagCreate(namespace as CFString, prefix as CFString, name as CFString,
                                                type, values as CFArray) else { return false }
        return CGImageMetadataSetTagWithPath(metadata, nil, "\(prefix):\(name)" as CFString, tag)
    }

    private static func strings(_ tag: CGImageMetadataTag) -> [String]? {
        guard let tags = CGImageMetadataTagCopyValue(tag) as? [CGImageMetadataTag] else { return nil }
        let values = tags.compactMap { CGImageMetadataTagCopyValue($0) as? String }
        return tags.count == values.count ? values : nil
    }

    private static func localizedText(_ metadata: CGImageMetadata, at path: String) -> String? {
        if let value = string(metadata, at: path + "[x-default]") { return value }
        guard let tag = CGImageMetadataCopyTagWithPath(metadata, nil, path as CFString) else { return nil }
        if let translations = strings(tag) { return translations.first ?? "" }
        return CGImageMetadataTagCopyValue(tag) as? String
    }

    private static func string(_ metadata: CGImageMetadata, at path: String) -> String? {
        CGImageMetadataCopyStringValueWithPath(metadata, nil, path as CFString) as String?
    }
}
