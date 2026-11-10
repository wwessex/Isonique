import Foundation

public struct ProjectGPXTrack: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public internal(set) var name: String
    public let segments: [[GPSCoordinates]]
    public internal(set) var isVisible: Bool

    public init(contentsOf url: URL) throws {
        id = UUID()
        name = url.deletingPathExtension().lastPathComponent
        segments = try GPXTrack.overlaySegments(from: url)
        isVisible = true
    }
}

public extension Library {
    @discardableResult
    mutating func addProjectGPXTrack(_ track: ProjectGPXTrack, to projectID: UUID) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }) else { return false }
        var tracks = projects[index].gpxTracks ?? []
        guard !tracks.contains(where: { $0.id == track.id }) else { return false }
        var track = track
        let names = Set(tracks.map(\.name))
        let base = track.name
        var suffix = 2
        while names.contains(track.name) {
            track.name = "\(base) (\(suffix))"
            suffix += 1
        }
        tracks.append(track)
        projects[index].gpxTracks = tracks
        return true
    }

    @discardableResult
    mutating func setProjectGPXTrackVisibility(_ visible: Bool, trackID: UUID, in projectID: UUID) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }),
              let trackIndex = projects[index].gpxTracks?.firstIndex(where: { $0.id == trackID }),
              projects[index].gpxTracks?[trackIndex].isVisible != visible else { return false }
        projects[index].gpxTracks?[trackIndex].isVisible = visible
        return true
    }

    @discardableResult
    mutating func removeProjectGPXTrack(_ trackID: UUID, from projectID: UUID) -> Bool {
        guard let index = projects.firstIndex(where: { $0.id == projectID }),
              var tracks = projects[index].gpxTracks,
              let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else { return false }
        tracks.remove(at: trackIndex)
        projects[index].gpxTracks = tracks.isEmpty ? nil : tracks
        return true
    }
}

extension Library {
    func validateProjectGPXTracks() throws {
        guard !albums.contains(where: { $0.gpxTracks?.isEmpty == false }) else {
            throw LibraryError.integrity("an album contains project GPX tracks")
        }
        for project in projects {
            guard let tracks = project.gpxTracks else { continue }
            let ids = Set(tracks.map(\.id))
            guard ids.count == tracks.count,
                  tracks.allSatisfy({ !$0.segments.isEmpty && $0.segments.allSatisfy { $0.count > 1 } }) else {
                throw LibraryError.integrity("invalid project GPX tracks")
            }
        }
    }
}
