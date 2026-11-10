import IsoniqueCore
import SwiftUI

extension Workspace {
    var placesProject: Collection? {
        presentation == .places ? selectedProject : nil
    }

    var visibleGPXTracks: [ProjectGPXTrack] {
        placesProject?.gpxTracks?.filter(\.isVisible) ?? []
    }

    func chooseProjectGPXTrack() {
        guard !busy, let project = placesProject, let url = chooseGPXTrackFile() else { return }
        Task { await importProjectGPXTrack(from: url, into: project.id) }
    }

    func importProjectGPXTrack(from url: URL, into projectID: UUID) async {
        guard !busy, let repository, placesProject?.id == projectID else { return }
        busy = true
        status = "Reading GPX track…"
        let task = Task.detached(priority: .userInitiated) { try ProjectGPXTrack(contentsOf: url) }
        let result = await withTaskCancellationHandler {
            await task.result
        } onCancel: {
            task.cancel()
        }
        busy = false

        do {
            try Task.checkCancellation()
            let track = try result.get()
            var draft = library
            guard self.repository === repository, draft.addProjectGPXTrack(track, to: projectID) else {
                throw LibraryError.integrity("the project or library changed while reading the track")
            }
            guard commit(draft) else { status = "GPX track import failed"; return }
            status = "Imported GPX track"
        } catch is CancellationError {
            status = "GPX track import cancelled"
        } catch {
            self.error = error.localizedDescription
            status = "GPX track import failed"
        }
    }

    func setGPXTrackVisibility(_ visible: Bool, trackID: UUID, in projectID: UUID) {
        guard !busy, placesProject?.id == projectID else { return }
        var draft = library
        guard draft.setProjectGPXTrackVisibility(visible, trackID: trackID, in: projectID),
              commit(draft) else { return }
        status = visible ? "GPX track shown" : "GPX track hidden"
    }

    func removeGPXTrack(_ trackID: UUID, from projectID: UUID) {
        guard !busy, placesProject?.id == projectID else { return }
        var draft = library
        guard draft.removeProjectGPXTrack(trackID, from: projectID), commit(draft) else { return }
        status = "Removed GPX track"
    }
}

struct ProjectGPXTracksMenu: View {
    @ObservedObject var model: Workspace
    let project: Collection
    @State private var pendingRemoval: ProjectGPXTrack?

    var body: some View {
        Menu("GPX Tracks", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            Button("Import GPX Track…", action: model.chooseProjectGPXTrack)
            if let tracks = project.gpxTracks {
                Divider()
                ForEach(tracks) { track in
                    Menu(track.name) {
                        if track.waypoints?.isEmpty == false {
                            Button("Assign Waypoint…") { model.openGPXWaypointAssignment(trackID: track.id) }
                                .disabled(!track.isVisible)
                        }
                        Button(track.isVisible ? "Hide Track" : "Show Track") {
                            model.setGPXTrackVisibility(!track.isVisible, trackID: track.id, in: project.id)
                        }
                        Button("Remove Track…", role: .destructive) { pendingRemoval = track }
                    }
                }
            }
        }
        .disabled(model.busy)
        .alert("Remove GPX Track?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        ), presenting: pendingRemoval) { track in
            Button("Remove Track", role: .destructive) { model.removeGPXTrack(track.id, from: project.id) }
            Button("Cancel", role: .cancel) {}
        } message: { track in
            Text("Remove “\(track.name)” from this project? Photos keep their assigned locations.")
        }
    }
}
