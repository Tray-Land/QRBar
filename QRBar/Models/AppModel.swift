import AppKit
import OSLog
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

    var tab: Tab = .create {
        didSet {
            if tab != oldValue {
                Log.app.info("Tab: \(String(describing: self.tab), privacy: .public)")
            }
        }
    }

    var page: Page = .main {
        didSet {
            if page != oldValue {
                Log.app.info("Page: \(String(describing: self.page), privacy: .public)")
            }
        }
    }

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
        Log.app.info("Popover opened (\(self.showCount) this launch)")
        loginItem.refresh()
    }

    /// Leaving the popover counts as being done with the current code, so it goes into history.
    func popoverDidClose() {
        Log.app.info("Popover closed")
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
            Log.export.error("Nothing to copy as \(format.title, privacy: .public)")
            return false
        }

        switch format {
        case .png: NSPasteboard.general.setPNG(data)
        case .svg: NSPasteboard.general.setSVG(data)
        }
        Log.export.info("Copied \(format.title, privacy: .public), \(data.count) bytes")
        recordHistory()
        return true
    }

    /// Returns to a code from history on the Create tab.
    func restore(_ entry: HistoryEntry) {
        Log.history.info("Restoring a \(entry.text.utf8.count)-byte entry at \(entry.correction.letter, privacy: .public)")
        recordHistory()
        create.restore(entry)
        recordHistory()
        tab = .create
        page = .main
    }

    /// Turns a scanned result into a new code on the Create tab.
    func makeCode(from text: String) {
        Log.read.info("Making a code from a \(text.utf8.count)-byte scan result")
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
            Log.export.error("Nothing to save as \(format.title, privacy: .public)")
            return false
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = "\(create.suggestedFileName).\(format.fileExtension)"
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .picturesDirectory, in: .userDomainMask).first

        guard let url = await runPanel(panel) else {
            Log.export.info("Save cancelled")
            return false
        }

        do {
            try data.write(to: url, options: .atomic)
            Log.export.info("Saved \(format.title, privacy: .public), \(data.count) bytes")
            recordHistory()
            return true
        } catch {
            Log.export.error("Couldn't save \(format.title, privacy: .public): \(String(describing: error), privacy: .public)")
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
            Log.read.info("Opening a .\(url.pathExtension, privacy: .public) file")
            await read.read(fileAt: url)
        } else {
            Log.read.info("Open cancelled")
        }
    }

    /// Hides the popover while the user selects part of the screen, then reads any codes in it.
    func scanScreen() async {
        tab = .read
        guard ScreenCapture.hasPermission else {
            Log.read.notice("No Screen Recording permission; requesting it")
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
            Log.read.info("Screen capture cancelled")
        case .failure(let error):
            Log.read.error("Screen capture failed: \(String(describing: error), privacy: .public)")
            read.showMessage("Couldn't capture the screen: \(error.localizedDescription)")
        }
    }

    /// Copies the diagnostic log, with this Mac's details and the current settings, as text.
    func copyLogs() async -> Bool {
        let settings = [
            "Settings: correction \(create.correction.letter), colors \(create.foreground.hex) on \(create.background.hex), drag \(create.dragFormat.title), copy/save \(create.saveFormat.title)",
            "Login item: \(String(describing: loginItem.status)), history: \(history.entries.count) entries",
            "Screen Recording permission: \(ScreenCapture.hasPermission ? "granted" : "not granted")",
            "Displays: " + NSScreen.screens.map { "\(Int($0.frame.width))×\(Int($0.frame.height)) @\($0.backingScaleFactor)x" }.joined(separator: ", "),
        ]

        do {
            let report = try await DiagnosticLog.report(header: DiagnosticLog.systemSummary + settings)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(report, forType: .string)
            Log.app.info("Copied the diagnostic log, \(report.utf8.count) bytes")
            return true
        } catch {
            Log.app.error("Couldn't read the log store: \(String(describing: error), privacy: .public)")
            NSAlert(error: error).runModal()
            return false
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
