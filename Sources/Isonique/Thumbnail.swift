import SwiftUI
import IsoniqueCore

extension View {
    func photoReviewAccessibility(_ photo: Photo, selected: Bool) -> some View {
        let rating: String
        if photo.rating == RatingRules.rejected {
            rating = String(localized: "Rejected")
        } else if photo.rating > 0 {
            rating = photo.rating == 1 ? String(localized: "1 star") : String(localized: "\(photo.rating) stars")
        } else {
            rating = String(localized: "Unrated")
        }
        let reviewState = photo.flagged ? String(localized: "\(rating), Flagged") : rating
        return accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityValue(reviewState)
    }
}

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

struct BrowserThumbnail: View {
    @EnvironmentObject private var model: Workspace
    let photo: Photo
    let original: URL?
    let maximum: Int
    var inList = false

    @State private var saved: (Request, CGImage)?

    private struct Request: Equatable {
        let key: OfflineViewerPreviews.Key
        let maximum: Int
        let revision: Int
    }

    var body: some View {
        let request = offlineRequest
        Group {
            if let original {
                Thumbnail(request: .init(photoID: photo.id, url: original, adjustments: photo.adjustments,
                                         maximum: maximum, revision: model.originalStatusRevision),
                          cache: model.thumbnailCache)
                    .frame(width: inList ? 34 : nil, height: inList ? 25 : nil)
            } else if let request, let (loaded, image) = saved, loaded == request {
                let preview = Image(decorative: image, scale: 1).resizable().scaledToFit()
                if inList {
                    HStack(spacing: 5) {
                        preview.frame(width: 34, height: 25)
                        offlineBadge
                    }
                } else {
                    preview.frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(alignment: .bottomTrailing) { offlineBadge.padding(4) }
                }
            } else if inList {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
                    .accessibilityLabel("Original unavailable").frame(width: 34)
            } else {
                Label("Original unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: request) {
            saved = nil
            guard let request,
                  let image = await model.offlineViewerPreviews.thumbnail(for: request.key, maximum: request.maximum),
                  !Task.isCancelled else { return }
            saved = (request, image)
        }
        .onDisappear { saved = nil }
    }

    private var offlineRequest: Request? {
        guard original == nil, let library = model.repository?.root,
              let key = OfflineViewerPreviews.Key(photo: photo, library: library) else { return nil }
        return Request(key: key, maximum: maximum, revision: model.originalStatusRevision)
    }

    private var offlineBadge: some View {
        Text("Offline")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.yellow)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(.black.opacity(0.85), in: Capsule())
            .accessibilityLabel(inList ? Text("\(photo.displayName), Offline preview") : Text("Offline preview"))
            .help("Saved preview. Original unavailable.")
    }
}
