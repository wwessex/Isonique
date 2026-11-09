import SwiftUI
import IsoniqueCore

struct Thumbnail: View {
    let request: ThumbnailCache.Request
    let cache: ThumbnailCache
    @State private var loaded: (request: ThumbnailCache.Request, image: CGImage)?

    var body: some View {
        Group {
            if let loaded, loaded.request == request {
                Image(decorative: loaded.image, scale: 1).resizable().scaledToFit()
            } else {
                Image(systemName: "photo").foregroundStyle(.secondary)
            }
        }.task(id: request) {
            do {
                let image = try await cache.image(for: request)
                guard !Task.isCancelled else { return }
                loaded = (request, image)
            } catch {
                if !Task.isCancelled { loaded = nil }
            }
        }.onDisappear {
            loaded = nil
        }
    }
}
