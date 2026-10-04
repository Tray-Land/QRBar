import AppKit
import Observation
import QRBarKit
import UniformTypeIdentifiers

/// State for the popover, which lives as long as the app so nothing is lost when it closes.
@Observable
final class AppModel {
    enum Tab: Hashable {
        case create
        case read
    }

    enum Page: Hashable {
        case main
        case settings
        case history
    }

    var tab: Tab = .create
    var page: Page = .main

    /// Changes every time the popover opens, so views can move focus.
    private(set) var showCount = 0

    let create = CreateModel()
    let read = ReadModel()
    let loginItem = LoginItem()
    let history = HistoryModel()

    @ObservationIgnored var presentPopover: () -> Void = {}
    @ObservationIgnored var dismissPopover: () -> Void = {}

    func popoverDidShow() {
        showCount += 1
        loginItem.refresh()
    }

    /// Leaving the popover counts as being done with the current code, so it goes into history.
    func popoverDidClose() {
        recordHistory()
    }

    /// Adds the current code to history. Called when it's copied, saved, or left behind, rather than
    /// on every keystroke.
    func recordHistory() {
        if let entry = create.historyEntry {
            history.record(entry)
        }
    }

    /// Puts the current code on the clipboard. Returns true once copied.
    func copyImage(as format: ExportFormat) -> Bool {
        guard let data = create.exportData(as: format) else {
            return false
        }

        switch format {
        case .png: NSPasteboard.general.setPNG(data)
        case .svg: NSPasteboard.general.setSVG(data)
        }
        recordHistory()
        return true
    }

    /// Returns to a code from history on the Create tab.
    func restore(_ entry: HistoryEntry) {
        recordHistory()
        create.restore(entry)
        recordHistory()
        tab = .create
        page = .main
    }

    /// Turns a scanned result into a new code on the Create tab.
    func makeCode(from text: String) {
        recordHistory()
        create.text = text
        tab = .create
    }

    // MARK: - Panels

    // Panels and the capture overlay take focus, which closes the transient popover, so close it
    // first and bring it back when they finish.

    /// Asks where to save the current code. Returns true once saved.
    func saveImage(as format: ExportFormat) async -> Bool {
        guard let data = create.exportData(as: format) else {
            return false
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(create.suggestedFileName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first

        guard let url = await runPanel(panel) else {
            return false
        }

        do {
            try data.write(to: url, options: .atomic)
            recordHistory()
            return true
        } catch {
            NSAlert(error: error).runModal()
            return false
        }
    }

    func openImageFile() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first

        if let url = await runPanel(panel) {
            await read.read(fileAt: url)
        }
    }

    /// Hides the popover while the user selects part of the screen, then reads any codes in it.
    func scanScreen() async {
        tab = .read
        guard ScreenCapture.hasPermission else {
            ScreenCapture.requestPermission()
            read.showPermissionMessage()
            return
        }

        dismissPopover()
        let result = await Result { try await ScreenCapture.captureSelection() }
        presentPopover()

        switch result {
        case .success(let data?):
            await read.read(imageData: data)
        case .success(nil):
            break // Cancelled with Esc.
        case .failure(let error):
            read.showMessage("Couldn't capture the screen: \(error.localizedDescription)")
        }
    }

    private func runPanel(_ panel: NSSavePanel) async -> URL? {
        dismissPopover()
        NSApp.activate()
        let response = await panel.begin()
        presentPopover()
        return response == .OK ? panel.url : nil
    }
}

private extension Result where Failure == any Error {
    init(catching body: () async throws -> Success) async {
        do {
            self = .success(try await body())
        } catch {
            self = .failure(error)
        }
    }
}
