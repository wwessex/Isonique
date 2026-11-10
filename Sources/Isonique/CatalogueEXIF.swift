import Foundation
import IsoniqueCore

extension Workspace {
    var canCatalogueSelectedEXIF: Bool { metadataEditingTargets.contains { $0.cameraEXIF == nil } }

    func catalogueSelectedEXIF() {
        let targets = Set(metadataEditingTargets.filter { $0.cameraEXIF == nil }.map(\.id))
        guard let repository, !targets.isEmpty else { return }
        let snapshot = library
        busy = true
        status = "Verifying originals and cataloguing EXIF…"
        let task = Task.detached(priority: .userInitiated) {
            var draft = snapshot
            let result = try repository.catalogueEXIF(for: targets, in: &draft)
            return (draft, result)
        }
        exifCatalogueTask = task
        Task {
            defer { exifCatalogueTask = nil; busy = false }
            do {
                let (draft, result) = try await task.value
                guard !task.isCancelled else { throw CancellationError() }
                busy = false
                if result.indexed > 0, !commit(draft) {
                    status = "EXIF catalogue update failed"
                    return
                }
                status = "Checked \(result.indexed) photos · \(result.withCaptureSettings) with EXIF settings"
                if !result.issues.isEmpty {
                    let details = result.issues.prefix(8).joined(separator: "\n")
                    error = "Skipped \(result.issues.count) photos.\n\n" + details
                }
                if selected == nil { selectAfterChange(preferred: selection) }
            } catch is CancellationError {
                status = "EXIF cataloguing cancelled"
            } catch {
                self.error = error.localizedDescription
                status = "EXIF catalogue update failed"
            }
        }
    }
}
