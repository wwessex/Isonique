import SwiftUI
import AppKit
import IsoniqueCore

struct HistogramView: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    @AppStorage("histogram.mode") private var mode = HistogramMode.luminance
    @State private var histogram: ToneHistogram?
    @State private var failure: String?

    private enum HistogramMode: String, CaseIterable, Identifiable {
        case luminance = "Luminance", rgb = "RGB", red = "Red", green = "Green", blue = "Blue"
        var id: Self { self }

        func series(from histogram: ToneHistogram) -> [([Int], Color)] {
            switch self {
            case .luminance: [(histogram.luminance, .white)]
            case .rgb: [(histogram.red, .red), (histogram.green, .green), (histogram.blue, .blue)]
            case .red: [(histogram.red, .red)]
            case .green: [(histogram.green, .green)]
            case .blue: [(histogram.blue, .blue)]
            }
        }
    }

    private struct Request: Equatable {
        let root: URL?
        let photoID: UUID
        let filename: String
        let referencedPath: String?
        let originalStatus: Int
        let adjustments: Adjustments
    }

    var body: some View {
        let request = Request(root: model.repository?.root, photoID: photo.id, filename: photo.filename,
                              referencedPath: photo.referencedPath, originalStatus: model.originalStatusRevision,
                              adjustments: photo.adjustments)
        VStack(alignment: .leading) {
            HStack {
                Text("HISTOGRAM").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Picker("Histogram display", selection: $mode) {
                    ForEach(HistogramMode.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().fixedSize()
            }
            Canvas { context, size in
                guard let histogram else { return }
                let series = mode.series(from: histogram)
                let maximum = Double(series.compactMap { $0.0.max() }.max() ?? 0)
                guard maximum > 0 else { return }
                var canvas = context
                if mode == .rgb { canvas.blendMode = .plusLighter }
                for (bins, color) in series {
                    let width = size.width / CGFloat(bins.count)
                    var path = Path()
                    for (index, count) in bins.enumerated() where count > 0 {
                        let height = size.height * Double(count) / maximum
                        path.addRect(CGRect(x: CGFloat(index) * width, y: size.height - height, width: width, height: height))
                    }
                    canvas.fill(path, with: .color(color.opacity(0.8)))
                }
            }.frame(height: 64).background(.black.opacity(0.25))
                .accessibilityLabel("\(mode.rawValue) distribution of the edited preview")
            Text(failure ?? "Edited preview · black to white").font(.caption2).foregroundStyle(.secondary)
        }.task(id: request) {
            histogram = nil; failure = nil
            guard let repository = model.repository else { return }
            let photo = self.photo
            let render = Task.detached(priority: .userInitiated) {
                let preview = try Renderer.render(repository.availableOriginalURL(photo), adjustments: photo.adjustments, maxDimension: 384)
                return try TonalTools.histogramChannels(preview)
            }
            let result = await withTaskCancellationHandler {
                await render.result
            } onCancel: { render.cancel() }
            guard !Task.isCancelled else { return }
            switch result { case .success(let values): histogram = values; case .failure(let error): failure = error.localizedDescription }
        }
    }
}

struct AutoStackView: View {
    @EnvironmentObject var model: Workspace
    @Environment(\.dismiss) var dismiss
    @State private var seconds = 2.0
    private var candidates: [Photo] { model.batchMode ? model.batchPhotos : model.photos }
    private var groups: [[UUID]] { AutoStack.groups(candidates, seconds: seconds) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Auto Stack by Capture Time").font(.title2.bold())
            Text("Groups photos when consecutive capture times are within the chosen gap. Uses the current view, or selected photos in batch mode. Existing stacks and photos without capture dates are left alone.")
            HStack { Text("Maximum gap"); Slider(value: $seconds, in: 0...60, step: 1); Text("\(Int(seconds)) sec").monospacedDigit() }
            Text("\(groups.count) new stacks · \(groups.reduce(0) { $0 + $1.count }) photos")
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create Stacks") {
                    var assignments: [UUID: UUID] = [:]
                    var picks: [StackPickChange] = []
                    for group in groups {
                        guard let first = group.first else { continue }
                        let stack = UUID()
                        for id in group { assignments[id] = stack }
                        picks.append(StackPickChange(stackID: stack, photoID: first, selectionID: first))
                    }
                    var draft = model.library
                    let previous = draft.updatePhotos(Set(assignments.keys)) { $0.stackID = assignments[$0.id] }
                    draft.applyStackPicks(picks)
                    guard model.commitPhotoChanges(draft, previous: previous) else { return }
                    model.status = "Created \(groups.count) stacks · Undo restores one photo per step"; dismiss()
                }.disabled(groups.isEmpty || model.busy).keyboardShortcut(.defaultAction)
            }
        }.padding(26).frame(width: 480)
    }
}

struct SlideshowView: View {
    @Environment(\.dismiss) var dismiss
    let photos: [Photo]
    let repository: LibraryRepository
    @State private var index = 0
    @State private var playing = true
    @State private var interval = SlideshowRules.defaultDisplayTime
    @State private var image: NSImage?
    @State private var failure: String?
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Color.black
                if let image { Image(nsImage: image).resizable().scaledToFit() }
                else if let failure { Text(failure).foregroundStyle(.white) }
                else { ProgressView() }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Button("Previous") { advance(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
                Button(playing ? "Pause" : "Play") { playing.toggle() }.keyboardShortcut(.space, modifiers: [])
                Button("Next") { advance(1) }.keyboardShortcut(.rightArrow, modifiers: [])
                Picker("Slide duration", selection: $interval) { Text("3 sec").tag(3.0); Text("5 sec").tag(5.0); Text("10 sec").tag(10.0) }.frame(width: 170)
                Text("\(index + 1) / \(photos.count)").monospacedDigit()
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text(photos[index].displayName).font(.caption).lineLimit(1)
        }.padding(18).frame(minWidth: 800, minHeight: 540)
        .task(id: index) {
            image = nil; failure = nil
            let photo = photos[index]
            let repository = self.repository
            let result = await Task.detached { () -> Result<CGImage, Error> in
                Result { try Renderer.render(repository.availableOriginalURL(photo), adjustments: photo.adjustments, maxDimension: 2400) }
            }.value
            guard !Task.isCancelled else { return }
            switch result { case .success(let cg): image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)); case .failure(let error): failure = error.localizedDescription }
        }
        .task(id: "\(playing)-\(interval)-\(index)-\(image != nil)-\(failure != nil)") {
            guard playing, image != nil || failure != nil else { return }
            do { try await Task.sleep(for: .seconds(interval)); guard !Task.isCancelled else { return }; advance(1) } catch { }
        }
    }
    private func advance(_ delta: Int) { index = (index + delta + photos.count) % photos.count }
}

struct ToneCurveGraph: View {
    let adjustments: Adjustments
    let input: ToneHistogram?
    var body: some View {
        Canvas { context, size in
            var diagonal = Path(); diagonal.move(to: CGPoint(x: 0, y: size.height)); diagonal.addLine(to: CGPoint(x: size.width, y: 0))
            context.stroke(diagonal, with: .color(.gray), lineWidth: 1)
            let points = [0, adjustments.curveShadows, adjustments.curveMidtones, adjustments.curveHighlights, 1]
            var curve = Path()
            for (index, value) in points.enumerated() {
                let point = CGPoint(x: Double(index) * size.width / 4, y: (1 - value) * size.height)
                if index == 0 { curve.move(to: point) } else { curve.addLine(to: point) }
            }
            context.stroke(curve, with: .color(.yellow), lineWidth: 2)
        }.frame(height: 100)
            .background { AdjustmentHistogramView(series: input?.rgbSeries ?? []).background(.black.opacity(0.25)) }
            .accessibilityLabel("Master tone curve and RGB input histogram")
    }
}
