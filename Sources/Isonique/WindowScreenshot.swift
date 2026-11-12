import AppKit
import ScreenCaptureKit
import Darwin

/// Captures only this app's window, including SwiftUI's composited layers.
@MainActor final class WindowScreenshot {
    static let shared = WindowScreenshot()
    private var started = false
    private var timer: Timer?
    private var frames = 0
    private var attempts = 0

    func startIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard !started, let index = arguments.firstIndex(of: "--screenshot") else { return }
        started = true
        guard arguments.indices.contains(index + 1),
              !arguments[index + 1].isEmpty,
              !arguments[index + 1].hasPrefix("--"),
              (arguments[index + 1] as NSString).pathExtension.lowercased() == "png" else {
            fail("Usage: --screenshot <file.png>")
        }
        let destination = URL(fileURLWithPath: arguments[index + 1])
        // Bound both window startup and asynchronous capture well below the checker deadline.
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
            self.fail("Window capture timed out")
        }
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.drawFrame(to: destination) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func drawFrame(to destination: URL) {
        attempts += 1
        guard let window = NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && $0.contentView != nil
        }), let view = window.contentView else {
            if attempts >= 600 { fail("No application window became visible") }
            return
        }
        view.needsDisplay = true
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        frames += 1
        guard frames >= 120 else { return }
        timer?.invalidate()
        Task {
            do {
                // Every supported release provides current-process capture without
                // requiring broad Screen Recording consent.
                let content = try await SCShareableContent.currentProcess
                guard let ownWindow = content.windows.first(where: {
                    $0.windowID == CGWindowID(window.windowNumber)
                }) else { fail("Application window is unavailable for capture") }
                let filter = SCContentFilter(desktopIndependentWindow: ownWindow)
                let configuration = SCStreamConfiguration()
                configuration.width = Int(ownWindow.frame.width * window.backingScaleFactor)
                configuration.height = Int(ownWindow.frame.height * window.backingScaleFactor)
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                    fail("Cannot encode window picture as PNG")
                }
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: destination, options: .atomic)
                print("Saved window screenshot: \(destination.path)")
                NSApplication.shared.terminate(nil)
            } catch { fail(error.localizedDescription) }
        }
    }

    private func fail(_ message: String) -> Never {
        fputs("Screenshot failed: \(message)\n", stderr)
        exit(1)
    }
}
