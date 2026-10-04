import Foundation
import OSLog
import Observation
import QRBarKit

/// A code made earlier, with everything needed to make it again.
struct HistoryEntry: Identifiable, Hashable, Codable {
    var id = UUID()
    var text: String
    var correction: QRErrorCorrection
    var foreground: QRColor
    var background: QRColor
    var date: Date

    private enum CodingKeys: String, CodingKey {
        case id, text, correction, foreground, background, date
    }

    init(text: String, correction: QRErrorCorrection, foreground: QRColor, background: QRColor, date: Date = .now) {
        self.text = text
        self.correction = correction
        self.foreground = foreground
        self.background = background
        self.date = date
    }

    // Stored as letters and hex strings so QRBarKit's types don't need to be Codable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        correction = QRErrorCorrection(rawValue: try container.decode(String.self, forKey: .correction)) ?? .medium
        foreground = QRColor(hex: try container.decode(String.self, forKey: .foreground)) ?? .black
        background = QRColor(hex: try container.decode(String.self, forKey: .background)) ?? .white
        date = try container.decode(Date.self, forKey: .date)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(text, forKey: .text)
        try container.encode(correction.rawValue, forKey: .correction)
        try container.encode(foreground.hex, forKey: .foreground)
        try container.encode(background.hex, forKey: .background)
        try container.encode(date, forKey: .date)
    }
}

/// Recently made codes, newest first. Each text appears once; making it again moves it to the top
/// with its latest colors and error correction.
@Observable
final class HistoryModel {
    private static let maxEntries = 50
    private static let key = "history"

    private(set) var entries: [HistoryEntry] {
        didSet {
            do {
                defaults.set(try JSONEncoder().encode(entries), forKey: Self.key)
            } catch {
                Log.history.error("Couldn't save history: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        guard let data = defaults.data(forKey: Self.key) else {
            entries = []
            return
        }

        do {
            entries = try JSONDecoder().decode([HistoryEntry].self, from: data)
            Log.history.info("Loaded \(self.entries.count) entries")
        } catch {
            entries = []
            Log.history.error("Couldn't load history (\(data.count) bytes): \(String(describing: error), privacy: .public)")
        }
    }

    func record(_ entry: HistoryEntry) {
        if let first = entries.first, first.text == entry.text, first.correction == entry.correction,
           first.foreground == entry.foreground, first.background == entry.background {
            return // Already on top; don't rewrite defaults for nothing.
        }

        Log.history.info("Recorded a \(entry.text.utf8.count)-byte entry at \(entry.correction.letter, privacy: .public)")
        var updated = entries.filter { $0.text != entry.text }
        updated.insert(entry, at: 0)
        entries = Array(updated.prefix(Self.maxEntries))
    }

    func remove(_ entry: HistoryEntry) {
        Log.history.info("Removed an entry")
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        Log.history.info("Cleared \(self.entries.count) entries")
        entries = []
    }
}
