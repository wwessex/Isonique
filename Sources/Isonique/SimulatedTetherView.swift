import CoreGraphics
import ImageIO
import IsoniqueCore
import SwiftUI
import UniformTypeIdentifiers

private actor SimulatedTetherCamera {
    private var files: [CameraImportFile: Data] = [:]
    private var nextShot = 0

    func connection() -> TetheredCameraConnection {
        TetheredCameraConnection(initialCatalogue: Array(files.keys), capture: { try await self.capture() },
                                 download: { try await self.download($0, to: $1) })
    }

    private func capture() throws -> AsyncThrowingStream<CameraImportFile, Error> {
        nextShot += 1
        let data = try image(for: nextShot)
        let name = String(format: "Simulator-%04d.jpg", nextShot)
        guard let file = CameraImportFile(components: ["Simulated Camera", name], byteCount: Int64(data.count)) else {
            throw LibraryError.unsupportedImage(name)
        }
        files[file] = data

        return AsyncThrowingStream { continuation in
            let delivery = Task {
                do {
                    try await Task.sleep(for: .seconds(3))
                    continuation.yield(file)
                    // Camera notifications may replay the same object.
                    continuation.yield(file)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in delivery.cancel() }
        }
    }

    private func download(_ file: CameraImportFile, to destination: URL) async throws {
        guard let data = files[file] else { throw DeviceImportError.disconnected }
        try await Task.sleep(for: .seconds(2))
        try data.write(to: destination)
    }

    private func image(for number: Int) throws -> Data {
        let size = CGSize(width: 640, height: 480)
        let data = NSMutableData()
        guard let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let encoder = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw LibraryError.unsupportedImage("simulated capture")
        }
        context.setFillColor(CGColor(red: 0.12, green: 0.15, blue: 0.23, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        context.setFillColor(CGColor(red: 0.2, green: 0.75, blue: 0.9, alpha: 1))
        for bit in 0..<Int.bitWidth where (number & (1 << bit)) != 0 {
            context.fill(CGRect(x: 80 + bit % 8 * 60, y: 80 + bit / 8 * 40, width: 44, height: 26))
        }
        guard let image = context.makeImage() else { throw LibraryError.unsupportedImage("simulated capture") }
        CGImageDestinationAddImage(encoder, image, nil)
        guard CGImageDestinationFinalize(encoder) else { throw LibraryError.unsupportedImage("simulated capture") }
        return data as Data
    }
}

struct SimulatedTetherView: View {
    @EnvironmentObject private var model: Workspace
    @Environment(\.dismiss) private var dismiss
    @State private var session = TetheredCaptureSession()
    @State private var camera = SimulatedTetherCamera()
    @State private var connected = false
    @State private var connecting = false
    @State private var shooting = false
    @State private var stopping = false
    @State private var message = "Connect the simulated camera to take a shot."

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Simulated Tethered Capture").font(.title2.bold())
            Text("Capture imports a generated photo into the current library.").foregroundStyle(.secondary)
            HStack {
                Text(connected ? "Camera connected" : "Camera disconnected")
                    .font(.headline)
                if shooting { ProgressView().controlSize(.small) }
            }
            Text(message).accessibilityIdentifier("TetherCaptureStatus")
            HStack {
                Button(connected ? "Disconnect" : "Connect") {
                    if connected { disconnect() }
                    else { connect() }
                }
                .disabled(connecting || (!connected && shooting))
                Button("Cancel Shot") { cancel() }.disabled(!shooting || stopping)
                Spacer()
                Button("Close") { dismiss() }.disabled(shooting)
                Button("Capture") { capture() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!connected || shooting || connecting || model.busy)
            }
        }
        .padding(24)
        .frame(width: 540)
        .interactiveDismissDisabled(shooting)
        .task { connect() }
        .onDisappear { Task { await session.disconnect() } }
    }

    private func connect() {
        guard !connecting else { return }
        connecting = true
        Task {
            defer { connecting = false }
            do {
                let connection = await camera.connection()
                try await session.connect(connection)
                connected = true
                message = "Ready for a single shot."
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func disconnect() {
        connected = false
        connecting = true
        stopping = true
        Task {
            defer { connecting = false }
            await session.disconnect()
            if !shooting { message = "Camera disconnected." }
        }
    }

    private func cancel() {
        stopping = true
        Task { await session.cancel() }
    }

    private func capture() {
        guard connected, !shooting, !model.busy, let repository = model.repository else { return }
        shooting = true
        stopping = false
        model.busy = true
        message = "Waiting for the shot and its files…"
        let library = model.library
        let projectID = library.projects.first(where: { model.scope == "project:\($0.id)" })?.id
        let albumID = library.albums.first(where: { $0.rule == nil && model.scope == "album:\($0.id)" })?.id
        Task {
            defer {
                shooting = false
                model.busy = false
            }
            do {
                let result = try await session.capture(repository: repository, library: library,
                                                       projectID: projectID, albumID: albumID)
                model.library = result.library
                if let selection = result.report.selection { model.selection = selection }
                if let error = result.report.errors.first {
                    message = error
                } else {
                    let prefix = result.report.cancelled ? "Shot cancelled. " : ""
                    message = "\(prefix)Imported \(result.report.imported) · duplicates \(result.report.duplicates)"
                }
                model.status = message
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
