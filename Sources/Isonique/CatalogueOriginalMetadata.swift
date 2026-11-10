import Foundation
import IsoniqueCore

enum OriginalMetadataKind: String {
    case exif = "EXIF"
    case gps = "GPS"

    func needsIndex(_ photo: Photo) -> Bool {
        switch self {
        case .exif: return photo.cameraEXIF == nil
        case .gps: return photo.gpsIndex == nil
        }
    }
}

extension Workspace {
    func canCatalogueSelected(_ kind: OriginalMetadataKind) -> Bool {
        !busy && metadataEditingTargets.contains(where: kind.needsIndex)
    }

    func catalogueSelected(_ kind: OriginalMetadataKind) {
        guard !busy, let repository else { return }
        let targets = Set(metadataEditingTargets.filter(kind.needsIndex).map(\.id))
        guard !targets.isEmpty else { return }
        let snapshot = library
        busy = true
        status = "Verifying originals and cataloguing \(kind.rawValue)…"
        let task = Task.detached(priority: .userInitiated) {
            var draft = snapshot
            let result: MetadataCatalogueResult
            switch kind {
            case .exif: result = try repository.catalogueEXIF(for: targets, in: &draft)
            case .gps: result = try repository.catalogueGPS(for: targets, in: &draft)
            }
            return (draft, result)
        }
        originalMetadataCatalogueTask = task
        Task {
            defer { originalMetadataCatalogueTask = nil; busy = false }
            do {
                let (draft, result) = try await task.value
                guard !task.isCancelled else { throw CancellationError() }
                busy = false
                if result.indexed > 0, !commit(draft) {
                    status = "\(kind.rawValue) catalogue update failed"
                    return
                }
                switch kind {
                case .exif: status = "Checked \(result.indexed) photos · \(result.withValues) with EXIF settings"
                case .gps: status = "Checked \(result.indexed) photos · \(result.withValues) with GPS coordinates"
                }
                if !result.issues.isEmpty {
                    let details = result.issues.prefix(8).joined(separator: "\n")
                    error = "Skipped \(result.issues.count) photos.\n\n" + details
                }
                if selected == nil { selectAfterChange(preferred: selection) }
            } catch is CancellationError {
                status = "\(kind.rawValue) cataloguing cancelled"
            } catch {
                self.error = error.localizedDescription
                status = "\(kind.rawValue) catalogue update failed"
            }
        }
    }
}
