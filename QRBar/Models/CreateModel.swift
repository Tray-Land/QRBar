import CoreGraphics
import Foundation
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
            encode()
        }
    }

    var foreground: QRColor {
        didSet { defaults.set(foreground.hex, forKey: Keys.foreground) }
    }

    var background: QRColor {
        didSet { defaults.set(background.hex, forKey: Keys.background) }
    }

    /// What dragging the code out produces.
    var dragFormat: ExportFormat {
        didSet { defaults.set(dragFormat.rawValue, forKey: Keys.dragFormat) }
    }

    /// What the Copy and Save buttons produce unless another format is picked from their menus.
    var saveFormat: ExportFormat {
        didSet { defaults.set(saveFormat.rawValue, forKey: Keys.saveFormat) }
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
        matrix = QRCodec.encode(text, correction: correction)
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
