import CoreGraphics
import Foundation

/// An sRGB color for rendering QR codes, usually opaque.
public struct QRColor: Hashable, Sendable {
    public var red: UInt8
    public var green: UInt8
    public var blue: UInt8
    public var alpha: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public static let black = QRColor(red: 0, green: 0, blue: 0)
    public static let white = QRColor(red: 255, green: 255, blue: 255)
    public static let clear = QRColor(red: 255, green: 255, blue: 255, alpha: 0)

    public var isOpaque: Bool { alpha == 255 }

    /// Parses `#RRGGBB` or `#RRGGBBAA` (the `#` is optional), or returns nil.
    public init?(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") {
            digits.removeFirst()
        }

        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit), var value = UInt32(digits, radix: 16) else {
            return nil
        }

        var alpha: UInt8 = 255
        if digits.count == 8 {
            alpha = UInt8(truncatingIfNeeded: value)
            value >>= 8
        }

        self.init(red: UInt8(truncatingIfNeeded: value >> 16), green: UInt8(truncatingIfNeeded: value >> 8), blue: UInt8(truncatingIfNeeded: value), alpha: alpha)
    }

    /// Formats as `#RRGGBB`, or `#RRGGBBAA` when not opaque.
    public var hex: String {
        isOpaque ? rgbHex : rgbHex + String(format: "%02X", alpha)
    }

    /// Formats as `#RRGGBB`, ignoring alpha.
    public var rgbHex: String {
        String(format: "#%02X%02X%02X", red, green, blue)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: CGFloat(alpha) / 255)
    }

    /// WCAG contrast ratio between two colors, from 1 (identical) to 21 (black on white).
    /// Translucent colors are judged over white, where codes are most often printed or pasted.
    public static func contrastRatio(_ a: QRColor, _ b: QRColor) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    private var relativeLuminance: Double {
        0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func linear(_ channel: UInt8) -> Double {
        let a = Double(alpha) / 255
        let c = Double(channel) / 255 * a + (1 - a)
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
}
