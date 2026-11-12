import AppKit
import PDFKit
import SwiftUI
import UniformTypeIdentifiers
import IsoniqueCore

enum NativeLightTablePrintBridge {
    enum Failure: LocalizedError {
        case invalidPDF
        var errorDescription: String? { "The generated Light Table document could not be opened." }
    }

    static func operation(pdfData: Data) throws -> NSPrintOperation {
        guard let document = PDFDocument(data: pdfData), document.pageCount == 1 else {
            throw Failure.invalidPDF
        }
        let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
        guard let operation = document.printOperation(for: info, scalingMode: .pageScaleToFit,
                                                      autoRotate: true) else { throw Failure.invalidPDF }
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        return operation
    }
}

extension Workspace {
    var lightTables: [LightTableLayout] { library.lightTables ?? [] }

    var activeLightTableID: UUID? {
        let prefix = "lightTable:"
        guard scope.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(scope.dropFirst(prefix.count)))
    }

    var activeLightTable: LightTableLayout? {
        guard let activeLightTableID else { return nil }
        return lightTables.first { $0.id == activeLightTableID }
    }

    var lightTableCandidatePhotos: [Photo] {
        if batchMode { return photos.filter { batchSelection.contains($0.id) } }
        return selected.map { [$0] } ?? []
    }

    var canCreateLightTable: Bool {
        !busy && !isViewingTrash && repository != nil && !lightTableCandidatePhotos.isEmpty
    }

    @discardableResult
    private func changeLightTables(_ message: String,
                                   _ change: (inout [LightTableLayout]) -> Void) -> Bool {
        var draft = library
        var layouts = draft.lightTables ?? []
        let previous = layouts
        change(&layouts)
        guard layouts != previous else { return false }
        draft.lightTables = layouts
        var nextHistory = history
        nextHistory.record(.lightTables(previous))
        guard commit(draft, history: nextHistory) else { return false }
        status = message
        return true
    }

    func createLightTable() {
        let photos = lightTableCandidatePhotos
        guard !photos.isEmpty else { return }
        let used = Set(lightTables.map { $0.name.lowercased() })
        var number = lightTables.count + 1
        while used.contains("light table \(number)") { number += 1 }
        let layout = LightTableLayout(name: "Light Table \(number)", photos: photos)
        guard changeLightTables("Created \(layout.name)", { $0.append(layout) }) else { return }
        batchMode = false
        batchSelection = []
        viewer = false
        places = false
        scope = "lightTable:\(layout.id)"
    }

    func duplicateLightTable(_ id: UUID) {
        guard var copy = lightTables.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name += " Copy"
        copy.items = copy.items.map {
            LightTableItem(photoID: $0.photoID, centerX: $0.centerX, centerY: $0.centerY,
                           width: $0.width, height: $0.height, rotation: $0.rotation,
                           zIndex: $0.zIndex)
        }
        guard changeLightTables("Duplicated Light Table", { $0.append(copy) }) else { return }
        scope = "lightTable:\(copy.id)"
    }

    func renameLightTable(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = changeLightTables("Renamed Light Table") { layouts in
            guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
            layouts[index].name = trimmed
        }
    }

    func deleteLightTable(_ id: UUID) {
        guard changeLightTables("Deleted Light Table", { $0.removeAll { $0.id == id } }) else { return }
        if activeLightTableID == id { scope = "all" }
    }

    func addSelection(toLightTable id: UUID) {
        let photos = lightTableCandidatePhotos
        guard !photos.isEmpty else { return }
        _ = changeLightTables("Added photos to Light Table") { layouts in
            guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
            layouts[index].add(photos)
        }
    }

    func moveLightTableItem(_ itemID: UUID, in layoutID: UUID, to point: CGPoint) {
        updateLightTable(layoutID, message: "Moved Light Table photo") { $0.move(itemID, to: point) }
    }

    func resizeLightTableItem(_ itemID: UUID, in layoutID: UUID, to size: CGSize) {
        updateLightTable(layoutID, message: "Resized Light Table photo") { $0.resize(itemID, to: size) }
    }

    func alignLightTableItems(_ itemIDs: Set<UUID>, in layoutID: UUID,
                              to alignment: LightTableAlignment) {
        updateLightTable(layoutID, message: alignment.rawValue) { $0.align(itemIDs, to: alignment) }
    }

    func rotateLightTableItems(_ itemIDs: Set<UUID>, in layoutID: UUID, by degrees: Double) {
        updateLightTable(layoutID, message: "Rotated Light Table photos") { $0.rotate(itemIDs, by: degrees) }
    }

    func bringLightTableItemsToFront(_ itemIDs: Set<UUID>, in layoutID: UUID) {
        updateLightTable(layoutID, message: "Brought photos to front") { $0.bringToFront(itemIDs) }
    }

    func sendLightTableItemsToBack(_ itemIDs: Set<UUID>, in layoutID: UUID) {
        updateLightTable(layoutID, message: "Sent photos to back") { $0.sendToBack(itemIDs) }
    }

    func removeLightTableItems(_ itemIDs: Set<UUID>, in layoutID: UUID) {
        updateLightTable(layoutID, message: "Removed photos from Light Table") { $0.remove(itemIDs) }
    }

    private func updateLightTable(_ id: UUID, message: String,
                                  _ update: (inout LightTableLayout) -> Void) {
        _ = changeLightTables(message) { layouts in
            guard let index = layouts.firstIndex(where: { $0.id == id }) else { return }
            update(&layouts[index])
        }
    }

    func saveLightTablePDF(_ layout: LightTableLayout) {
        guard !busy, let repository else { return }
        let panel = NSSavePanel()
        panel.title = "Save Light Table"
        panel.prompt = "Save PDF"
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(layout.name).pdf"
        panel.message = "Saves the arranged Light Table using full-resolution adjustments. Originals remain unchanged."
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        busy = true
        status = "Rendering Light Table PDF…"
        let photos = library.photos
        Task {
            let failure = await Task.detached(priority: .userInitiated) { () -> String? in
                do {
                    try LightTableOutput.writePDF(layout: layout, photos: photos,
                                                  repository: repository, to: destination)
                    return nil
                } catch { return error.localizedDescription }
            }.value
            busy = false
            error = failure
            status = failure == nil ? "Saved \(destination.lastPathComponent)" : "Light Table PDF failed"
        }
    }

    func printLightTable(_ layout: LightTableLayout) {
        guard !busy, let repository else { return }
        busy = true
        status = "Rendering Light Table for printing…"
        let photos = library.photos
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try LightTableOutput.pdfData(layout: layout, photos: photos, repository: repository) }
            }.value
            busy = false
            switch result {
            case .success(let data):
                do {
                    let operation = try NativeLightTablePrintBridge.operation(pdfData: data)
                    status = operation.run() ? "Print job sent" : "Printing cancelled"
                } catch {
                    self.error = error.localizedDescription
                    status = "Light Table printing failed"
                }
            case .failure(let failure):
                error = failure.localizedDescription
                status = "Light Table rendering failed"
            }
        }
    }
}

struct LightTableWorkspace: View {
    @EnvironmentObject private var model: Workspace
    let layout: LightTableLayout
    @State private var selectedItemIDs: Set<UUID> = []
    @State private var actualSize = false
    @State private var name = ""

    private var selectedItems: Set<UUID> {
        selectedItemIDs.intersection(layout.items.map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("Light Table name", text: $name)
                    .textFieldStyle(.roundedBorder).frame(width: 190)
                    .onSubmit { model.renameLightTable(layout.id, to: name) }
                Text("\(layout.items.count) photos").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(actualSize ? "Fit" : "100%") { actualSize.toggle() }
                    .help(actualSize ? "Fit the complete canvas" : "Inspect the canvas at 100%")
                Menu("Arrange") {
                    ForEach(LightTableAlignment.allCases) { alignment in
                        Button(alignment.rawValue) {
                            model.alignLightTableItems(selectedItems, in: layout.id, to: alignment)
                        }.disabled(selectedItems.count < 2)
                    }
                    Divider()
                    Button("Rotate Left 5°") {
                        model.rotateLightTableItems(selectedItems, in: layout.id, by: -5)
                    }.disabled(selectedItems.isEmpty)
                    Button("Rotate Right 5°") {
                        model.rotateLightTableItems(selectedItems, in: layout.id, by: 5)
                    }.disabled(selectedItems.isEmpty)
                    Divider()
                    Button("Bring to Front") {
                        model.bringLightTableItemsToFront(selectedItems, in: layout.id)
                    }.disabled(selectedItems.isEmpty)
                    Button("Send to Back") {
                        model.sendLightTableItemsToBack(selectedItems, in: layout.id)
                    }.disabled(selectedItems.isEmpty)
                    Button("Remove from Light Table", role: .destructive) {
                        model.removeLightTableItems(selectedItems, in: layout.id)
                        selectedItemIDs = []
                    }.disabled(selectedItems.isEmpty)
                }
                Menu("Layout") {
                    Button("Add Browser Selection") { model.addSelection(toLightTable: layout.id) }
                        .disabled(model.lightTableCandidatePhotos.isEmpty)
                    Button("Duplicate Layout") { model.duplicateLightTable(layout.id) }
                    Button("Delete Layout", role: .destructive) { model.deleteLightTable(layout.id) }
                }
                Button("Save PDF…") { model.saveLightTablePDF(layout) }.disabled(layout.items.isEmpty)
                Button("Print…") { model.printLightTable(layout) }.disabled(layout.items.isEmpty)
            }.padding(12)
            Divider()
            LightTableCanvas(layout: layout, selectedItemIDs: $selectedItemIDs,
                             actualSize: actualSize, model: model)
        }
        .onAppear { name = layout.name }
        .onChange(of: layout.id) { _, _ in selectedItemIDs = []; name = layout.name }
        .onChange(of: layout.name) { _, value in if name != value { name = value } }
        .onChange(of: layout.items.map(\.id)) { _, ids in selectedItemIDs.formIntersection(ids) }
    }
}

enum LightTableCanvasScale {
    static func value(viewport: CGSize, canvas: CGSize, actualSize: Bool) -> CGFloat {
        guard !actualSize else { return 1 }
        guard viewport.width.isFinite, viewport.height.isFinite,
              canvas.width > 0, canvas.height > 0 else { return 1 }
        return min(1, max(0.05,
            min((viewport.width - 40) / canvas.width, (viewport.height - 40) / canvas.height)))
    }
}

private struct LightTableCanvas: View {
    let layout: LightTableLayout
    @Binding var selectedItemIDs: Set<UUID>
    let actualSize: Bool
    @ObservedObject var model: Workspace

    var body: some View {
        GeometryReader { proxy in
            let scale = LightTableCanvasScale.value(viewport: proxy.size,
                canvas: CGSize(width: layout.canvasWidth, height: layout.canvasHeight),
                actualSize: actualSize)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color(white: 0.09))
                        .overlay(GridPattern().opacity(0.25))
                        .contentShape(Rectangle())
                        .onTapGesture { selectedItemIDs = [] }
                    ForEach(layout.items.sorted { $0.zIndex < $1.zIndex }) { item in
                        if let photo = model.library.photos.first(where: { $0.id == item.photoID }) {
                            LightTableCard(photo: photo, item: item, scale: scale,
                                           actualSize: actualSize,
                                           selected: selectedItemIDs.contains(item.id), model: model,
                                           select: { additive in
                                               if additive {
                                                   if !selectedItemIDs.insert(item.id).inserted {
                                                       selectedItemIDs.remove(item.id)
                                                   }
                                               } else { selectedItemIDs = [item.id] }
                                           },
                                           move: { model.moveLightTableItem(item.id, in: layout.id, to: $0) },
                                           resize: { model.resizeLightTableItem(item.id, in: layout.id, to: $0) })
                                .zIndex(Double(item.zIndex + 1))
                        }
                    }
                }
                .frame(width: layout.canvasWidth * scale, height: layout.canvasHeight * scale)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .shadow(radius: 10)
                .padding(20)
            }
        }
        .background(Color(white: 0.035))
        .accessibilityLabel("Light Table Canvas")
    }
}

private struct GridPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            stride(from: 0.0, through: size.width, by: 40).forEach {
                path.move(to: CGPoint(x: $0, y: 0)); path.addLine(to: CGPoint(x: $0, y: size.height))
            }
            stride(from: 0.0, through: size.height, by: 40).forEach {
                path.move(to: CGPoint(x: 0, y: $0)); path.addLine(to: CGPoint(x: size.width, y: $0))
            }
            context.stroke(path, with: .color(.white.opacity(0.12)), lineWidth: 0.5)
        }
    }
}

private struct LightTableCard: View {
    let photo: Photo
    let item: LightTableItem
    let scale: CGFloat
    let actualSize: Bool
    let selected: Bool
    @ObservedObject var model: Workspace
    let select: (Bool) -> Void
    let move: (CGPoint) -> Void
    let resize: (CGSize) -> Void
    @GestureState private var drag = CGSize.zero
    @GestureState private var sizeDrag = CGSize.zero

    private var liveSize: CGSize {
        CGSize(width: max(48, item.width + sizeDrag.width / scale),
               height: max(48, item.height + sizeDrag.height / scale))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            LightTableImage(photo: photo, fullResolution: actualSize && selected, model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { select(false) }
            Button { select(true) } label: {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: max(14, 20 * scale)))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, selected ? Color.accentColor : Color.black.opacity(0.55))
            }.buttonStyle(.plain).padding(max(4, 8 * scale)).frame(maxWidth: .infinity, maxHeight: .infinity,
                                                                    alignment: .topLeading)
            if selected {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: max(12, 16 * scale), weight: .bold))
                    .padding(max(4, 7 * scale)).background(.black.opacity(0.7), in: Circle())
                    .padding(max(3, 5 * scale))
                    .highPriorityGesture(resizeGesture)
                    .help("Drag to resize")
            }
        }
        .frame(width: liveSize.width * scale, height: liveSize.height * scale)
        .overlay(Rectangle().stroke(selected ? Color.accentColor : .white.opacity(0.18),
                                    lineWidth: selected ? 3 : 1))
        .rotationEffect(.degrees(item.rotation))
        .position(x: item.centerX * scale + drag.width, y: item.centerY * scale + drag.height)
        .gesture(moveGesture)
        .accessibilityLabel("\(photo.displayName), Light Table photo")
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                select(false)
                move(CGPoint(x: item.centerX + value.translation.width / scale,
                             y: item.centerY + value.translation.height / scale))
            }
    }

    private var resizeGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .updating($sizeDrag) { value, state, _ in state = value.translation }
            .onEnded { value in
                resize(CGSize(width: item.width + value.translation.width / scale,
                              height: item.height + value.translation.height / scale))
            }
    }
}

private struct LightTableImage: View {
    let photo: Photo
    let fullResolution: Bool
    @ObservedObject var model: Workspace
    @State private var loaded: (request: Request, image: CGImage)?

    private struct Request: Equatable {
        let photoID: UUID
        let url: URL
        let adjustments: Adjustments
        let fullResolution: Bool
        let revision: Int
    }

    var body: some View {
        Group {
            if let loaded, loaded.request == request {
                Image(decorative: loaded.image, scale: 1).resizable().scaledToFit()
            } else { Image(systemName: "photo").foregroundStyle(.secondary) }
        }
        .task(id: request) {
            guard let request else { loaded = nil; return }
            do {
                let frame = try await model.viewerRenderCache.frame(url: request.url,
                    adjustments: request.adjustments,
                    maximum: request.fullResolution ? nil : 1200,
                    revision: request.revision)
                guard !Task.isCancelled else { return }
                loaded = (request, frame.image)
            } catch { if !Task.isCancelled { loaded = nil } }
        }
    }

    private var request: Request? {
        guard let repository = model.repository,
              let url = try? repository.availableOriginalURL(photo) else { return nil }
        return Request(photoID: photo.id, url: url, adjustments: photo.adjustments,
                       fullResolution: fullResolution, revision: model.originalStatusRevision)
    }
}
