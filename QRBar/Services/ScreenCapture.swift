import CoreGraphics
import Foundation
import OSLog
import QRBarKit

/// Lets the user select part of the screen with the system screenshot UI (crosshair, Space for a
/// window, Esc to cancel) — the macOS counterpart of the Windows snipping overlay.
enum ScreenCapture {
    /// Screen Recording permission. Without it captures only show the wallpaper.
    static var hasPermission: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt the first time; later it only adds QRBar to the list in System Settings.
    static func requestPermission() {
        CGRequestScreenCaptureAccess()
    }

    static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    /// Returns PNG data for the selected area, or nil when the user pressed Esc.
    static func captureSelection() async throws -> Data? {
        let url = URL.temporaryDirectory.appending(path: "QRBar-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-t", "png", url.path(percentEncoded: false)] // Interactive, silent.

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { _ in continuation.resume() }
            do {
                try process.run()
            } catch {
                Log.read.error("Couldn't run screencapture: \(String(describing: error), privacy: .public)")
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }

        // Esc leaves no file behind (and a non-zero exit status); that's a cancel, not an error.
        let data = try? Data(contentsOf: url)
        Log.read.info("screencapture exited with status \(process.terminationStatus), \(data.map { "\($0.count) bytes" } ?? "no file", privacy: .public)")
        return data
    }
}
