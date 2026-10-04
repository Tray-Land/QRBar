import CoreGraphics
import Foundation

/// An opaque sRGB color for rendering QR codes.
public struct QRColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = QRColor(red: 0, green: 0, blue: 0)
    public static let white = QRColor(red: 255, green: 255, blue: 255)

    /// Parses `#RRGGBB` (the `#` is optional), or returns nil.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }

        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let rgb = UInt32(digits, radix: 16) else {
            return nil
        }

        self.init(red: UInt8(truncatingIfNeeded: rgb >> 16), green: UInt8(truncatingIfNeeded: rgb >> 8), blue: UInt8(truncatingIfNeeded: rgb))
    }

    /// Formats as `#RRGGBB`.
    public var hex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }

    /// WCAG contrast ratio between two colors, from 1 (identical) to 21 (black on white).
    public static func contrastRatio(_ a: QRColor, _ b: QRColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * Self.linear(red) + 0.7152 * Self.linear(green) + 0.0722 * Self.linear(blue)
    }

    private static func linear(_ channel: UInt8) -> Double {
        let c = Double(channel) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
