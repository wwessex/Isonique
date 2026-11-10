import IsoniqueCore
import SwiftUI
import UniformTypeIdentifiers

struct GPXLocationEdit: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let libraryRoot: URL
    let targets: [Target]

    struct Target: Equatable, Sendable {
        let id: UUID
        let name: String
        let captureDate: String
        let gpsIndex: GPSIndex?
        let locationOverride: PhotoLocationOverride?
        let coordinates: GPSCoordinates?

        init(_ photo: Photo) {
            id = photo.id
            name = photo.displayName
            captureDate = photo.captureDate
            gpsIndex = photo.gpsIndex
            locationOverride = photo.locationOverride
            coordinates = photo.cataloguedLocation
        }
    }

    struct Settings: Equatable, Sendable {
        let timeZone: TimeZone
        let maximumGap: Int
    }

    struct Row: Identifiable, Sendable {
        enum Result: Sendable {
            case invalidCaptureTime, noMatch
            case matched(GPXTrack.Match)
        }

        let target: Target
        let result: Result
        var id: UUID { target.id }

        var change: PhotoLocationChange? {
            guard case .matched(let match) = result, target.coordinates != match.coordinates else { return nil }
            return PhotoLocationChange(photoID: id, location: .assigned(match.coordinates))
        }
    }

    struct Preview: Sendable {
        let editID: UUID
        let settings: Settings
        let rows: [Row]

        func changes(excluding ids: Set<UUID>) -> [PhotoLocationChange] {
            rows.compactMap { ids.contains($0.id) ? nil : $0.change }
        }
    }

    func preview(track: GPXTrack, settings: Settings) throws -> Preview {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        var camera = utc
        camera.timeZone = settings.timeZone
        let rows = try targets.map { target in
            try Task.checkCancellation()
            let result: Row.Result
            if let timestamp = Self.captureTime(target.captureDate, utc: utc, camera: camera) {
                if let match = track.match(at: timestamp, maximumGap: TimeInterval(settings.maximumGap)) {
                    result = .matched(match)
                } else {
                    result = .noMatch
                }
            } else {
                result = .invalidCaptureTime
            }
            return Row(target: target, result: result)
        }
        return Preview(editID: id, settings: settings, rows: rows)
    }

    private static func captureTime(_ value: String, utc: Calendar, camera: Calendar) -> Date? {
        guard let wallTime = CaptureDateCorrection.parse(value) else { return nil }
        if utc.timeZone == camera.timeZone { return wallTime }
        let time = utc.dateComponents([.hour, .minute, .second], from: wallTime)
        let date = utc.dateComponents([.year, .month, .day], from: wallTime)
        guard let day = camera.date(from: date),
              camera.dateComponents([.year, .month, .day], from: day) == date,
              let hour = time.hour, let minute = time.minute, let second = time.second,
              let first = camera.date(bySettingHour: hour, minute: minute, second: second, of: day,
                                      matchingPolicy: .strict, repeatedTimePolicy: .first),
              camera.isDate(first, inSameDayAs: day),
              let last = camera.date(bySettingHour: hour, minute: minute, second: second, of: day,
                                     matchingPolicy: .strict, repeatedTimePolicy: .last),
              first == last else { return nil }
        return first
    }
}

extension Workspace {
    func chooseGPXTrack() {
        guard !metadataEditingTargets.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.title = String(localized: "Choose a GPX Track")
        panel.allowedContentTypes = [UTType(filenameExtension: "gpx") ?? .xml]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { openGPXLocationEditor(url: url) }
    }

    func openGPXLocationEditor(url: URL) {
        let targets = metadataEditingTargets
        guard let repository, !targets.isEmpty else { return }
        gpxLocationEditor = GPXLocationEdit(url: url, libraryRoot: repository.root,
                                          targets: targets.map(GPXLocationEdit.Target.init))
    }

    @discardableResult
    func applyGPXLocations(_ preview: GPXLocationEdit.Preview, excluding ids: Set<UUID>) -> Bool {
        guard !busy, let edit = gpxLocationEditor, edit.id == preview.editID else { return false }
        let current = Dictionary(uniqueKeysWithValues: metadataEditingTargets.map { ($0.id, GPXLocationEdit.Target($0)) })
        guard repository?.root == edit.libraryRoot, current.count == edit.targets.count,
              edit.targets.allSatisfy({ current[$0.id] == $0 }) else {
            error = "The library, selection, capture times or locations have changed. Reopen Match GPX Track to review them."
            return false
        }
        return commitLocationChanges(preview.changes(excluding: ids))
    }
}

struct GPXLocationView: View {
    let edit: GPXLocationEdit
    @EnvironmentObject private var model: Workspace
    @State private var timeZoneName = TimeZone.current.identifier
    @State private var maximumGap = 120
    @State private var track: GPXTrack?
    @State private var readError: String?
    @State private var preview: GPXLocationEdit.Preview?
    @State private var excluded = Set<UUID>()

    private var timeZone: TimeZone? { TimeZone(identifier: timeZoneName.trimmingCharacters(in: .whitespacesAndNewlines)) }

    var body: some View {
        let settings = timeZone.map { GPXLocationEdit.Settings(timeZone: $0, maximumGap: maximumGap) }
        let ready = preview.flatMap { $0.settings == settings ? $0 : nil }
        let count = ready?.changes(excluding: excluded).count ?? 0
        VStack(alignment: .leading, spacing: 12) {
            Text("Match GPX Track").font(.title2.bold())
            Text(edit.url.lastPathComponent).foregroundStyle(.secondary)
            HStack(spacing: 12) {
                Text("Camera time zone").accessibilityHidden(true)
                TextField("Camera time zone", text: $timeZoneName, prompt: Text("Europe/London"))
                    .labelsHidden().accessibilityLabel("Camera time zone").autocorrectionDisabled()
                Picker("Maximum track gap", selection: $maximumGap) {
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("2 minutes").tag(120)
                    Text("5 minutes").tag(300)
                    Text("15 minutes").tag(900)
                }.fixedSize()
            }
            Text("Use the time zone set on the camera, for example Europe/London or UTC. For a repeated clock time, enter a fixed offset such as UTC+01:00.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Between fixes, matches use the two surrounding points in the same segment if the gap is within the limit.")
                .font(.caption).foregroundStyle(.secondary)
            if let readError {
                Text(readError).foregroundStyle(.red)
            } else if settings == nil {
                Text("Enter a valid time zone to preview the matches.").foregroundStyle(.secondary)
            } else if let ready {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(ready.rows) { row in
                            rowView(row)
                            Divider()
                        }
                    }.padding(.trailing, 8)
                }.frame(height: 244)
                Text(count == 1 ? "1 photo will change" : "\(count) photos will change")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView(track == nil ? "Reading GPX track…" : "Matching capture times…")
                    .frame(maxWidth: .infinity, minHeight: 244)
            }
            HStack {
                Spacer()
                Button("Cancel") { model.gpxLocationEditor = nil }.keyboardShortcut(.cancelAction)
                Button("Apply Locations") {
                    if let ready, model.applyGPXLocations(ready, excluding: excluded) || model.error != nil {
                        model.gpxLocationEditor = nil
                    }
                }.disabled(count == 0)
            }
        }
        .padding(24).frame(width: 620)
        .task {
            do {
                let url = edit.url
                track = try await Self.background { try GPXTrack(contentsOf: url) }
            } catch is CancellationError {
                return
            } catch {
                readError = error.localizedDescription
            }
        }
        .task(id: track == nil ? nil : settings) {
            guard let track, let settings else { return }
            let edit = edit
            do {
                preview = try await Self.background { try edit.preview(track: track, settings: settings) }
            } catch is CancellationError {
                return
            } catch {
                readError = error.localizedDescription
            }
        }
    }

    private static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler {
            let value = try await task.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            task.cancel()
        }
    }

    private func rowView(_ row: GPXLocationEdit.Row) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.target.name).fontWeight(.medium)
                if !row.target.captureDate.isEmpty {
                    Text(row.target.captureDate).font(.caption).foregroundStyle(.secondary)
                }
                rowDetail(row).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if row.change != nil {
                Toggle("Apply to \(row.target.name)", isOn: Binding(
                    get: { !excluded.contains(row.id) },
                    set: { if $0 { excluded.remove(row.id) } else { excluded.insert(row.id) } }
                )).toggleStyle(.checkbox).labelsHidden()
            }
        }
    }

    @ViewBuilder
    private func rowDetail(_ row: GPXLocationEdit.Row) -> some View {
        switch row.result {
        case .invalidCaptureTime:
            Text("Missing, invalid or ambiguous capture time")
        case .noMatch:
            Text("No unambiguous track match within the gap limit")
        case .matched(let match):
            let point = format(match.coordinates)
            if row.change == nil {
                Text("Location already matches · \(point)")
            } else {
                Text(match.method == .exact ? "Exact match · \(point)" : "Interpolated match · \(point)")
                if let existing = row.target.coordinates {
                    Text("Current location · \(format(existing))")
                } else if row.target.gpsIndex == nil && row.target.locationOverride == nil {
                    Text("Original GPS unindexed")
                }
            }
        }
    }

    private func format(_ point: GPSCoordinates) -> String {
        let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0...6))
        return "\(point.latitude.formatted(format)), \(point.longitude.formatted(format))"
    }
}
