import IsoniqueCore
import SwiftUI

extension GPXWaypoint {
    var displayName: String { name ?? String(localized: "Unnamed Waypoint") }

    var coordinateLabel: String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6))
        return "\(coordinates.latitude.formatted(format))°, \(coordinates.longitude.formatted(format))°"
    }
}

struct GPXWaypointAssignment: Identifiable {
    let projectID: UUID
    let trackID: UUID
    let trackName: String
    let waypoints: [GPXWaypoint]
    let initialWaypointID: UUID
    let initialPhotoID: UUID?
    let locationEdit: PhotoLocationEdit

    var id: UUID { locationEdit.id }
}

extension Workspace {
    private var waypointAssignmentPhotos: [Photo] {
        filteredPhotos(advancedQuery: advancedSearch, includingUnlocated: true)
    }

    func openGPXWaypointAssignment(trackID: UUID, waypointID: UUID? = nil) {
        guard !busy, let repository, let project = placesProject,
              let track = visibleGPXTracks.first(where: { $0.id == trackID }),
              let waypoints = track.waypoints, let firstWaypoint = waypoints.first else { return }
        let initialWaypoint = waypointID ?? firstWaypoint.id
        guard waypoints.contains(where: { $0.id == initialWaypoint }) else { return }
        let candidates = waypointAssignmentPhotos
        let initialPhoto = candidates.first { $0.id == selection }?.id
        gpxWaypointAssignment = GPXWaypointAssignment(
            projectID: project.id, trackID: trackID, trackName: track.name, waypoints: waypoints,
            initialWaypointID: initialWaypoint, initialPhotoID: initialPhoto,
            locationEdit: PhotoLocationEdit(action: .assign, libraryRoot: repository.root, photos: candidates)
        )
    }

    @discardableResult
    func applyGPXWaypointAssignment(_ assignmentID: UUID, waypointID: UUID, photoIDs: Set<UUID>) -> Bool {
        guard !busy, !photoIDs.isEmpty, let assignment = gpxWaypointAssignment, assignment.id == assignmentID,
              let waypoint = assignment.waypoints.first(where: { $0.id == waypointID }) else { return false }
        let edit = assignment.locationEdit
        let currentWaypoint = visibleGPXTracks.first { $0.id == assignment.trackID }?
            .waypoints?.first { $0.id == waypointID }
        guard repository?.root == edit.libraryRoot, placesProject?.id == assignment.projectID,
              currentWaypoint == waypoint else {
            error = "The project or waypoint changed. Reopen the waypoint preview to review it."
            return false
        }

        let reviewedPhotos = edit.photos.filter { photoIDs.contains($0.id) }
        let currentPhotos = Dictionary(uniqueKeysWithValues: waypointAssignmentPhotos
            .filter { photoIDs.contains($0.id) }.map { ($0.id, $0) })
        guard reviewedPhotos.count == photoIDs.count, reviewedPhotos.allSatisfy({ reviewed in
            guard let current = currentPhotos[reviewed.id] else { return false }
            return current.gpsIndex == reviewed.gpsIndex && current.locationOverride == reviewed.locationOverride
        }) else {
            error = "The selected photos or their locations changed. Reopen the waypoint preview to review them."
            return false
        }

        let changes = edit.changes(to: waypoint.coordinates, restrictedTo: photoIDs)
        guard commitLocationChanges(changes) else { return false }
        gpxWaypointAssignment = nil
        return true
    }
}

struct GPXWaypointAssignmentView: View {
    @EnvironmentObject private var model: Workspace
    let assignment: GPXWaypointAssignment
    @State private var waypointID: UUID
    @State private var photoIDs: Set<UUID>

    init(assignment: GPXWaypointAssignment) {
        self.assignment = assignment
        _waypointID = State(initialValue: assignment.initialWaypointID)
        _photoIDs = State(initialValue: Set([assignment.initialPhotoID].compactMap { $0 }))
    }

    var body: some View {
        let waypoint = assignment.waypoints.first { $0.id == waypointID }
        let count = assignment.locationEdit.changes(to: waypoint?.coordinates, restrictedTo: photoIDs).count
        VStack(alignment: .leading, spacing: 12) {
            Text("Assign GPX Waypoint").font(.title2.bold())
            Picker("Waypoint in \(assignment.trackName)", selection: $waypointID) {
                ForEach(assignment.waypoints) { option in
                    Text("\(option.displayName) · \(option.coordinateLabel)").tag(option.id)
                }
            }
            if assignment.locationEdit.photos.isEmpty {
                Text("No photo versions match the current project filters.").foregroundStyle(.secondary)
            } else {
                Text("Choose the photo versions to assign this location to.").foregroundStyle(.secondary)
                List(assignment.locationEdit.photos) { photo in
                    Toggle(isOn: Binding(
                        get: { photoIDs.contains(photo.id) },
                        set: { if $0 { photoIDs.insert(photo.id) } else { photoIDs.remove(photo.id) } }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(photo.displayName)
                            locationPreview(for: photo, waypoint: waypoint)
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.toggleStyle(.checkbox)
                }.frame(height: 245)
            }
            HStack {
                Text(count == 1 ? "1 photo version will change" : "\(count) photo versions will change")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.gpxWaypointAssignment = nil }.keyboardShortcut(.cancelAction)
                Button("Assign Location") {
                    if !model.applyGPXWaypointAssignment(assignment.id, waypointID: waypointID, photoIDs: photoIDs),
                       model.error != nil {
                        model.gpxWaypointAssignment = nil
                    }
                }.keyboardShortcut(.defaultAction).disabled(count == 0)
            }
        }.padding(24).frame(width: 580)
    }

    @ViewBuilder
    private func locationPreview(for photo: Photo, waypoint: GPXWaypoint?) -> some View {
        if let location = photo.cataloguedLocation {
            if location == waypoint?.coordinates {
                Text("Already at this waypoint")
            } else {
                let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6))
                Text("Current location · \(location.latitude.formatted(format))°, \(location.longitude.formatted(format))°")
            }
        } else if photo.hasCataloguedLocation {
            Text("No current location")
        } else {
            Text("Original GPS unindexed")
        }
    }
}
