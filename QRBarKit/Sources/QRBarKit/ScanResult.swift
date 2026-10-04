import Foundation

/// One decoded code, with a launchable link when the text is one.
public struct ScanResult: Identifiable, Hashable, Sendable {
    private static let launchableSchemes: Set<String> = ["http", "https", "mailto", "tel", "sms", "geo"]

    public let id = UUID()
    public let text: String
    public let link: URL?

    public init(text: String) {
        self.text = text
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), Self.launchableSchemes.contains(scheme) {
            link = url
        } else {
            link = nil
        }
    }
}

public enum QRFileName {
    /// A short, filesystem-safe name for a code's image, e.g. "QR example.com-path" (no extension).
    public static func suggested(for text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where trimmed.lowercased().hasPrefix(prefix) {
            trimmed.removeFirst(prefix.count)
        }

        let unsafe = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.whitespacesAndNewlines).union(.controlCharacters)
        let cleaned = String(trimmed.unicodeScalars.prefix(40).map { unsafe.contains($0) ? "-" : Character($0) })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-."))
        return cleaned.isEmpty ? "QR code" : "QR \(cleaned)"
    }
}
