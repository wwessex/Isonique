import SwiftUI
import AppKit
import PDFKit
import IsoniqueCore
import UniformTypeIdentifiers

enum PrintPresetStorage {
    static let key = "print.presets"
    static let lastOptionsKey = "print.lastOptions"
    static func decode(_ data: Data) -> [PrintPreset] {
        (try? JSONDecoder().decode([PrintPreset].self, from: data)) ?? []
    }
    static func encode(_ presets: [PrintPreset]) -> Data {
        (try? JSONEncoder().encode(presets)) ?? Data()
    }
}

enum NativePrintBridge {
    enum Failure: LocalizedError {
        case invalidPDF
        case operationUnavailable
        var errorDescription: String? {
            switch self {
            case .invalidPDF: return "The generated print document could not be opened."
            case .operationUnavailable: return "macOS could not create a print operation for this document."
            }
        }
    }

    static func operation(pdfData: Data, options: PrintLayoutOptions) throws -> NSPrintOperation {
        guard let document = PDFDocument(data: pdfData), document.pageCount > 0 else { throw Failure.invalidPDF }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.paperSize = options.pageSize.portraitDimensions
        info.orientation = options.orientation == .portrait ? .portrait : .landscape
        info.topMargin = 0
        info.bottomMargin = 0
        info.leftMargin = 0
        info.rightMargin = 0
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleNone,
                                                      autoRotate: false) else {
            throw Failure.operationUnavailable
        }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation
    }
}

extension Workspace {
    var printPhotos: [Photo] { batchMode ? batchPhotos : photos }
    var canPrintPhotos: Bool { !busy && !isViewingTrash && repository != nil && !printPhotos.isEmpty }

    func openPrintLayout() {
        guard canPrintPhotos else { return }
        showPrintOptions = true
    }

    func savePrintPDF(_ options: PrintLayoutOptions, photos: [Photo]) {
        guard !busy, let repository, !photos.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "Save Contact Sheet"
        panel.prompt = "Save PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = options.style == .proof ? "Isonique Proofs.pdf" : "Isonique Contact Sheet.pdf"
        panel.message = "Saves the printable layout as a PDF. Original photos remain unchanged."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        status = "Rendering \(photos.count) photos for PDF…"
        Task {
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    try PrintLayout.writePDF(photos: photos, repository: repository,
                                             options: options, to: destination)
                    return nil
                } catch { return error.localizedDescription }
            }.value
            busy = false
            error = failure
            status = failure == nil ? "Saved \(destination.lastPathComponent)" : "PDF export failed"
        }
    }

    func printLayout(_ options: PrintLayoutOptions, photos: [Photo]) {
        guard !busy, let repository, !photos.isEmpty else { return }
        busy = true
        status = "Rendering \(photos.count) photos for printing…"
        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Data, Error> in
                Result { try PrintLayout.pdfData(photos: photos, repository: repository, options: options) }
            }.value
            busy = false
            switch result {
            case .success(let data):
                do {
                    let operation = try NativePrintBridge.operation(pdfData: data, options: options)
                    status = operation.run() ? "Print job sent" : "Printing cancelled"
                } catch {
                    self.error = error.localizedDescription
                    status = "Printing failed"
                }
            case .failure(let failure):
                error = failure.localizedDescription
                status = "Print rendering failed"
            }
        }
    }
}

struct PrintLayoutView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PrintPresetStorage.key) private var savedPresets = Data()
    @AppStorage(PrintPresetStorage.lastOptionsKey) private var lastOptions = Data()
    @State private var options = PrintLayoutOptions()
    @State private var presetName = ""
    @State private var pageIndex = 0

    private var photos: [Photo] { model.printPhotos }
    private var presets: [PrintPreset] { PrintPresetStorage.decode(savedPresets) }
    private var plan: Result<PrintLayoutPlan, Error> {
        Result { try PrintLayout.plan(photos: photos, options: options) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(options.style == .proof ? "Print Proofs" : "Print Contact Sheet").font(.title2.bold())
                Spacer()
                Text("\(photos.count) photos").foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 22) {
                controls.frame(width: 310)
                preview.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save PDF…") { perform(native: false) }.disabled(planValue == nil)
                Button("Print…") { perform(native: true) }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(planValue == nil)
            }
        }
        .padding(24)
        .frame(width: 850, height: 690)
        .onAppear {
            options = (try? JSONDecoder().decode(PrintLayoutOptions.self, from: lastOptions)) ?? PrintLayoutOptions()
        }
        .onChange(of: pageCount) { _, count in pageIndex = min(pageIndex, max(0, count - 1)) }
    }

    private var controls: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Menu("Load Preset") {
                        ForEach(presets) { preset in Button(preset.name) { options = preset.options } }
                    }.disabled(presets.isEmpty)
                    Menu("Delete Preset") {
                        ForEach(presets) { preset in
                            Button(preset.name) { savePresets(presets.filter { $0.id != preset.id }) }
                        }
                    }.disabled(presets.isEmpty)
                }
                Picker("Layout", selection: $options.style) {
                    ForEach(PrintLayoutStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Paper", selection: $options.pageSize) {
                    ForEach(PrintPageSize.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Orientation", selection: $options.orientation) {
                    ForEach(PrintOrientation.allCases) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
                Stepper("Margins: \(Int(options.marginPoints)) pt", value: $options.marginPoints,
                        in: 0...144, step: 6)
                if options.style == .contactSheet {
                    Stepper("Columns: \(options.columns)", value: $options.columns, in: 1...10)
                    Stepper("Rows: \(options.rows)", value: $options.rows, in: 1...10)
                }
                Picker("Caption", selection: $options.caption) {
                    ForEach(PrintCaptionStyle.allCases) { Text($0.rawValue).tag($0) }
                }
                Picker("Output Colour", selection: $options.colourMode) {
                    ForEach(PrintColourMode.allCases) { Text($0.rawValue).tag($0) }
                }
                Text("sRGB is the predictable general-purpose choice. Display P3 retains a wide-gamut RGB image space in the PDF. Black and White converts only the print output.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                TextField("Preset name", text: $presetName)
                Button("Save Print Preset") {
                    let trimmed = presetName.trimmingCharacters(in: .whitespacesAndNewlines)
                    var updated = presets.filter { $0.name.localizedCaseInsensitiveCompare(trimmed) != .orderedSame }
                    updated.append(PrintPreset(name: trimmed, options: options))
                    savePresets(updated)
                    presetName = ""
                }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || planValue == nil)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var preview: some View {
        switch plan {
        case .failure(let error):
            ContentUnavailableView("Preview Unavailable", systemImage: "exclamationmark.triangle",
                                   description: Text(error.localizedDescription))
        case .success(let plan):
            VStack(spacing: 10) {
                PrintPagePreview(plan: plan, pageIndex: pageIndex, model: model)
                HStack {
                    Button { pageIndex = max(0, pageIndex - 1) } label: { Image(systemName: "chevron.left") }
                        .disabled(pageIndex == 0)
                    Text("Page \(pageIndex + 1) of \(plan.pages.count)").monospacedDigit()
                    Button { pageIndex = min(plan.pages.count - 1, pageIndex + 1) } label: { Image(systemName: "chevron.right") }
                        .disabled(pageIndex + 1 >= plan.pages.count)
                }
                Text("Preview uses cached thumbnails. PDF and Print render the saved full-resolution adjustments.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var planValue: PrintLayoutPlan? { try? plan.get() }
    private var pageCount: Int { planValue?.pages.count ?? 0 }

    private func savePresets(_ presets: [PrintPreset]) {
        savedPresets = PrintPresetStorage.encode(presets)
    }

    private func perform(native: Bool) {
        guard planValue != nil else { return }
        lastOptions = (try? JSONEncoder().encode(options)) ?? Data()
        let selectedOptions = options
        let selectedPhotos = photos
        dismiss()
        DispatchQueue.main.async {
            if native { model.printLayout(selectedOptions, photos: selectedPhotos) }
            else { model.savePrintPDF(selectedOptions, photos: selectedPhotos) }
        }
    }
}

private struct PrintPagePreview: View {
    let plan: PrintLayoutPlan
    let pageIndex: Int
    @ObservedObject var model: Workspace

    var body: some View {
        GeometryReader { geometry in
            let scale = min(geometry.size.width / plan.pageSize.width,
                            geometry.size.height / plan.pageSize.height)
            let pageSize = CGSize(width: plan.pageSize.width * scale, height: plan.pageSize.height * scale)
            let offset = CGPoint(x: (geometry.size.width - pageSize.width) / 2,
                                 y: (geometry.size.height - pageSize.height) / 2)
            ZStack(alignment: .topLeading) {
                Rectangle().fill(.white).shadow(radius: 4)
                    .frame(width: pageSize.width, height: pageSize.height)
                    .position(x: offset.x + pageSize.width / 2, y: offset.y + pageSize.height / 2)
                if plan.pages.indices.contains(pageIndex) {
                    ForEach(plan.pages[pageIndex].cells) { cell in
                        cellView(cell)
                            .frame(width: cell.frame.width * scale, height: cell.frame.height * scale)
                            .position(x: offset.x + cell.frame.midX * scale,
                                      y: offset.y + (plan.pageSize.height - cell.frame.midY) * scale)
                    }
                }
            }
        }
        .accessibilityLabel("Print Layout Preview")
    }

    private func cellView(_ cell: PrintLayoutCell) -> some View {
        VStack(spacing: 2) {
            if let repository = model.repository,
               let url = try? repository.availableOriginalURL(cell.photo) {
                Thumbnail(request: .init(photoID: cell.photo.id, url: url,
                                         adjustments: cell.photo.adjustments, maximum: 480,
                                         revision: model.originalStatusRevision),
                          cache: model.thumbnailCache)
                    .grayscale(plan.options.colourMode == .monochrome ? 1 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Image(systemName: "exclamationmark.triangle").foregroundStyle(.gray)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            if !cell.caption.isEmpty {
                Text(cell.caption).font(.system(size: 8)).foregroundStyle(.black)
                    .lineLimit(plan.options.style == .proof ? 3 : 2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }.padding(2)
    }
}
