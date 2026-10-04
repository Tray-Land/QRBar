import AppKit
import Observation
import QRBarKit
import UniformTypeIdentifiers

/// The Read tab: finds codes in a pasted, dropped, opened, or captured image.
@Observable
final class ReadModel {
    static let idleMessage = "Codes found in the image appear here."

    private(set) var sourceImage: CGImage?
    private(set) var results: [ScanResult] = []
    private(set) var message: String? = ReadModel.idleMessage
    private(set) var isReading = false
    private(set) var needsScreenPermission = false

    func read(imageData data: Data) async {
        await read { await QRReader.image(from: data) }
    }

    func read(fileAt url: URL) async {
        await read { await QRReader.image(contentsOf: url) }
    }

    /// Reads an image file or image data from the pasteboard (a copied file, screenshot, or picture).
    func readPasteboard(_ pasteboard: NSPasteboard = .general) async {
        let imageFiles = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL]

        if let url = imageFiles?.first {
            await read(fileAt: url)
            return
        }

        let imageType = pasteboard.types?.first { UTType($0.rawValue)?.conforms(to: .image) == true }
        if let imageType, let data = pasteboard.data(forType: imageType) {
            await read(imageData: data)
            return
        }

        showMessage("There's no image on the clipboard. Copy a picture that contains a QR code.")
    }

    func showMessage(_ text: String) {
        results = []
        message = text
        needsScreenPermission = false
    }

    func showPermissionMessage() {
        showMessage("To read codes on screen, allow QRBar under Screen & System Audio Recording in System Settings, then try again.")
        needsScreenPermission = true
    }

    private func read(_ load: () async -> CGImage?) async {
        results = []
        message = nil
        needsScreenPermission = false
        isReading = true
        defer { isReading = false }

        guard let image = await load() else {
            showMessage("Couldn't open that image.")
            return
        }

        sourceImage = image
        do {
            let payloads = try await QRReader.decode(image)
            if payloads.isEmpty {
                showMessage("No QR code found. Try a sharper or larger image.")
            } else {
                results = payloads.map(ScanResult.init)
            }
        } catch {
            showMessage("Couldn't read that image: \(error.localizedDescription)")
        }
    }
}
