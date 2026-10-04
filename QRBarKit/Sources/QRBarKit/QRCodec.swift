import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// QR error-correction levels, lowest (densest data) to highest (most damage-tolerant).
public enum QRErrorCorrection: String, CaseIterable, Identifiable, Sendable {
    case low = "L"
    case medium = "M"
    case quartile = "Q"
    case high = "H"

    public var id: Self { self }

    /// The single letter used by the QR spec.
    public var letter: String { rawValue }

    public var title: String {
        switch self {
        case .low: "Low (7%)"
        case .medium: "Medium (15%)"
        case .quartile: "Quartile (25%)"
        case .high: "High (30%)"
        }
    }
}

/// A QR code as a square grid of modules, including its quiet zone.
public struct QRMatrix: Hashable, Sendable {
    public let size: Int
    private let modules: [Bool]

    init(size: Int, modules: [Bool]) {
        precondition(modules.count == size * size)
        self.size = size
        self.modules = modules
    }

    public func isDark(x: Int, y: Int) -> Bool {
        modules[y * size + x]
    }
}

/// Encodes QR codes and renders them as images.
public enum QRCodec {
    /// Modules of blank margin around the symbol. The spec asks for 4; 2 reads fine on screens and
    /// keeps the code larger in the preview.
    public static let quietZone = 2

    /// Codes below this contrast ratio are hard for many scanners to read.
    public static let minReadableContrast = 3.0

    /// Builds the module grid for `text`, or nil when it's empty or too long to encode.
    public static func encode(_ text: String, correction: QRErrorCorrection) -> QRMatrix? {
        guard !text.isEmpty, let symbol = QREncoder.encode(Array(text.utf8), correction: correction) else {
            return nil
        }

        let size = symbol.size + 2 * quietZone
        var modules = [Bool](repeating: false, count: size * size)
        for y in 0..<symbol.size {
            for x in 0..<symbol.size where symbol.modules[y * symbol.size + x] {
                modules[(y + quietZone) * size + x + quietZone] = true
            }
        }

        return QRMatrix(size: size, modules: modules)
    }

    /// The most UTF-8 bytes a code can hold at `correction`.
    public static func capacity(for correction: QRErrorCorrection) -> Int {
        let version = QREncoder.maxVersion
        return (QREncoder.dataCodewords(version: version, correction: correction) * 8 - QREncoder.dataBits(byteCount: 0, version: version)) / 8
    }

    /// The QR version (1–40) of a matrix made by ``encode(_:correction:)``.
    public static func version(of matrix: QRMatrix) -> Int {
        (matrix.size - 2 * quietZone - 17) / 4
    }

    /// The largest whole-pixel scale that keeps the image at or under `maxPixels` wide.
    public static func scale(for matrix: QRMatrix, maxPixels: Int) -> Int {
        max(1, maxPixels / matrix.size)
    }

    /// Renders the matrix with `scale` pixels per module.
    public static func render(
        _ matrix: QRMatrix,
        scale: Int = 1,
        foreground: QRColor = .black,
        background: QRColor = .white
    ) -> CGImage? {
        let width = matrix.size * scale
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: width,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            return nil
        }

        context.setShouldAntialias(false)
        context.setFillColor(background.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: width))
        context.setFillColor(foreground.cgColor)

        // Core Graphics puts the origin bottom-left, so flip rows. Fill horizontal runs, not single modules.
        for y in 0..<matrix.size {
            let top = (matrix.size - 1 - y) * scale
            var x = 0
            while x < matrix.size {
                guard matrix.isDark(x: x, y: y) else {
                    x += 1
                    continue
                }

                let start = x
                while x < matrix.size, matrix.isDark(x: x, y: y) {
                    x += 1
                }

                context.fill(CGRect(x: start * scale, y: top, width: (x - start) * scale, height: scale))
            }
        }

        return context.makeImage()
    }

    /// Renders the matrix as an SVG document, one unit per module, scaled to `pixels` wide by default.
    public static func svg(
        _ matrix: QRMatrix,
        pixels: Int,
        foreground: QRColor = .black,
        background: QRColor = .white
    ) -> String {
        // One subpath per horizontal run of dark modules, like `render`.
        var path = ""
        for y in 0..<matrix.size {
            var x = 0
            while x < matrix.size {
                guard matrix.isDark(x: x, y: y) else {
                    x += 1
                    continue
                }

                let start = x
                while x < matrix.size, matrix.isDark(x: x, y: y) {
                    x += 1
                }

                path += "M\(start) \(y)h\(x - start)v1h-\(x - start)z"
            }
        }

        let size = matrix.size
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(pixels)" height="\(pixels)" viewBox="0 0 \(size) \(size)" shape-rendering="crispEdges">
        <rect width="\(size)" height="\(size)" fill="\(background.hex)"/>
        <path d="\(path)" fill="\(foreground.hex)"/>
        </svg>

        """
    }

    /// Encodes an image as PNG.
    public static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }

        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
