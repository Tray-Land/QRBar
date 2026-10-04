import CoreGraphics
import Foundation
import OSLog
import Observation
import QRBarKit

/// The Create tab: text in, QR code out, re-encoded shortly after typing pauses.
@Observable
final class CreateModel {
    /// Big enough for a crisp paste into documents; each module stays a whole number of pixels.
    nonisolated static let exportPixels = 1024
    private static let previewPixels = 512
    private static let maxSavedTextLength = 2000

    var text: String {
        didSet {
            defaults.set(String(text.prefix(Self.maxSavedTextLength)), forKey: Keys.text)
            scheduleEncode()
        }
    }

    var correction: QRErrorCorrection {
        didSet {
            defaults.set(correction.rawValue, forKey: Keys.correction)
            Log.create.info("Error correction: \(self.correction.letter, privacy: .public)")
            encode()
        }
    }

    var foreground: QRColor {
        didSet {
            defaults.set(foreground.hex, forKey: Keys.foreground)
            logColors()
        }
    }

    var background: QRColor {
        didSet {
            defaults.set(background.hex, forKey: Keys.background)
            logColors()
        }
    }

    /// What dragging the code out produces.
    var dragFormat: ExportFormat {
        didSet {
            defaults.set(dragFormat.rawValue, forKey: Keys.dragFormat)
            Log.settings.info("Drag format: \(self.dragFormat.title, privacy: .public)")
        }
    }

    /// What the Copy and Save buttons produce unless another format is picked from their menus.
    var saveFormat: ExportFormat {
        didSet {
            defaults.set(saveFormat.rawValue, forKey: Keys.saveFormat)
            Log.settings.info("Copy and save format: \(self.saveFormat.title, privacy: .public)")
        }
    }

    private(set) var matrix: QRMatrix?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var encodeTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        text = defaults.string(forKey: Keys.text) ?? ""
        correction = defaults.string(forKey: Keys.correction).flatMap(QRErrorCorrection.init) ?? .medium
        foreground = defaults.string(forKey: Keys.foreground).flatMap(QRColor.init(hex:)) ?? .black
        background = defaults.string(forKey: Keys.background).flatMap(QRColor.init(hex:)) ?? .white
        dragFormat = defaults.string(forKey: Keys.dragFormat).flatMap(ExportFormat.init) ?? .png
        saveFormat = defaults.string(forKey: Keys.saveFormat).flatMap(ExportFormat.init) ?? .png
        Log.create.info("""
            Restored settings: correction \(self.correction.letter, privacy: .public) (saved: \(defaults.string(forKey: Keys.correction) ?? "none", privacy: .public)), \
            colors \(self.foreground.hex, privacy: .public) on \(self.background.hex, privacy: .public), \
            drag \(self.dragFormat.title, privacy: .public), copy/save \(self.saveFormat.title, privacy: .public), \
            text \(self.text.utf8.count) bytes
            """)
        encode()
    }

    var isTooLong: Bool { matrix == nil && !text.isEmpty }

    var hasLowContrast: Bool {
        matrix != nil && QRColor.contrastRatio(foreground, background) < QRCodec.minReadableContrast
    }

    /// Rendered at whole pixels per module so the preview stays sharp at any display scale.
    var previewImage: CGImage? {
        matrix.flatMap { QRCodec.render($0, scale: QRCodec.scale(for: $0, maxPixels: Self.previewPixels), foreground: foreground, background: background) }
    }

    var suggestedFileName: String { QRFileName.suggested(for: text) }

    /// A snapshot of the current code for copying, saving, or dragging, in the drag format.
    var export: QRExport? {
        matrix.map { QRExport(matrix: $0, foreground: foreground, background: background, fileName: suggestedFileName, format: dragFormat) }
    }

    func exportData(as format: ExportFormat) -> Data? {
        export?.data(as: format)
    }

    /// The current code and its settings, or nil when there's nothing to encode.
    var historyEntry: HistoryEntry? {
        matrix.map { _ in HistoryEntry(text: text, correction: correction, foreground: foreground, background: background) }
    }

    /// Brings back a code from history, settings and all.
    func restore(_ entry: HistoryEntry) {
        foreground = entry.foreground
        background = entry.background
        correction = entry.correction
        text = entry.text
        encode()
    }

    func resetColors() {
        foreground = .black
        background = .white
    }

    private func scheduleEncode() {
        encodeTask?.cancel()
        encodeTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else {
                return
            }

            encode()
        }
    }

    private func encode() {
        encodeTask?.cancel()
        let start = ContinuousClock.now
        matrix = QRCodec.encode(text, correction: correction)
        let elapsed = ContinuousClock.now - start

        let bytes = text.utf8.count
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        if let matrix {
            Log.create.info("Encoded \(bytes) bytes (\(self.text.count) characters, \(lines) lines) at \(self.correction.letter, privacy: .public) as version \(QRCodec.version(of: matrix)), \(matrix.size) modules, in \(elapsed, privacy: .public)")
        } else if bytes > 0 {
            Log.create.notice("Too long: \(bytes) bytes (\(self.text.count) characters, \(lines) lines) at \(self.correction.letter, privacy: .public); capacity is \(QRCodec.capacity(for: self.correction)) bytes")
        }
    }

    private func logColors() {
        Log.create.info("Colors: \(self.foreground.hex, privacy: .public) on \(self.background.hex, privacy: .public), contrast \(QRColor.contrastRatio(self.foreground, self.background), format: .fixed(precision: 2))")
    }

    private enum Keys {
        static let text = "lastText"
        static let correction = "errorCorrection"
        static let foreground = "foregroundColor"
        static let background = "backgroundColor"
        static let dragFormat = "dragFormat"
        static let saveFormat = "saveFormat"
    }
}

/// An immutable copy of a code and its colors, rendered at export size on demand.
nonisolated struct QRExport: Sendable {
    let matrix: QRMatrix
    let foreground: QRColor
    let background: QRColor
    let fileName: String
    /// The format offered when dragged.
    let format: ExportFormat

    func data(as format: ExportFormat) -> Data? {
        let scale = QRCodec.scale(for: matrix, maxPixels: CreateModel.exportPixels)
        switch format {
        case .png:
            return QRCodec.render(matrix, scale: scale, foreground: foreground, background: background)
                .flatMap(QRCodec.pngData)
        case .svg:
            return Data(QRCodec.svg(matrix, pixels: matrix.size * scale, foreground: foreground, background: background).utf8)
        }
    }
}
