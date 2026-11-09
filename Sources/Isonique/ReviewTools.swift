import SwiftUI
import AppKit
import IsoniqueCore

struct HistogramView: View {
    @EnvironmentObject var model: Workspace
    let photo: Photo
    @State private var bins = [Int]()
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading) {
            Text("LUMINANCE HISTOGRAM").font(.caption).foregroundStyle(.secondary)
            Canvas { context, size in
                let maximum = Double(bins.max() ?? 1)
                guard maximum > 0 else { return }
                var path = Path()
                for (index, count) in bins.enumerated() {
                    let x = Double(index) * size.width / 256
                    path.addRect(CGRect(x: x, y: size.height * (1 - Double(count) / maximum), width: max(1, size.width / 256), height: size.height * Double(count) / maximum))
                }
                context.fill(path, with: .color(.white.opacity(0.8)))
            }.frame(height: 64).background(.black.opacity(0.25)).accessibilityLabel("Luminance distribution of the edited preview")
            Text(failure ?? "Edited preview · black to white").font(.caption2).foregroundStyle(.secondary)
        }.task(id: "\(photo.id)-\(model.originalStatusRevision)-\(photo.adjustments)") {
            bins = []; failure = nil
            guard let repository = model.repository else { return }
            let photo = self.photo
            let result = await Task.detached { () -> Result<[Int], Error> in
                Result { try TonalTools.histogram(Renderer.render(repository.availableOriginalURL(photo), adjustments: photo.adjustments, maxDimension: 384)) }
            }.value
            guard !Task.isCancelled else { return }
            switch result { case .success(let values): bins = values; case .failure(let error): failure = error.localizedDescription }
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
                    for group in groups { let stack = UUID(); for id in group { assignments[id] = stack } }
                    var draft = model.library
                    let previous = draft.updatePhotos(Set(assignments.keys)) { $0.stackID = assignments[$0.id] }
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
    // -[RKSlideshowPreset init] 0x10009ef9f -> setDisplayTime: with f64 3.0.
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
        }.frame(height: 100).background(.black.opacity(0.25)).accessibilityLabel("Master tone curve at quarter, half and three-quarter input brightness")
    }
}
