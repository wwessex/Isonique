import Foundation

/// Cheap local identity for transient render caches. Refresh also invalidates cached reads.
struct OriginalFileStamp: Equatable {
    let volume: UInt64
    let inode: UInt64
    let size: UInt64
    let modified: Date
    let created: Date

    init?(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let volume = attrs[.systemNumber] as? NSNumber,
              let inode = attrs[.systemFileNumber] as? NSNumber,
              let size = attrs[.size] as? NSNumber,
              let modified = attrs[.modificationDate] as? Date,
              let created = attrs[.creationDate] as? Date else { return nil }
        self.volume = volume.uint64Value
        self.inode = inode.uint64Value
        self.size = size.uint64Value
        self.modified = modified
        self.created = created
    }
}
