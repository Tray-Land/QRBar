import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
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

/// Encodes QR codes with Core Image and renders them as images.
public enum QRCodec {
    /// Modules of blank margin around the symbol. The spec asks for 4; 2 reads fine on screens and
    /// keeps the code larger in the preview.
    public static let quietZone = 2

    /// Codes below this contrast ratio are hard for many scanners to read.
    public static let minReadableContrast = 3.0

    private static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    /// Builds the module grid for `text`, or nil when it's empty or too long to encode.
    public static func encode(_ text: String, correction: QRErrorCorrection) -> QRMatrix? {
        guard !text.isEmpty else {
            return nil
        }

        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = correction.rawValue

        // One pixel per module. Core Image returns nil when the message exceeds QR capacity.
        guard let output = filter.outputImage else {
            return nil
        }

        let extent = output.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, width == height else {
            return nil
        }

        var pixels = [UInt8](repeating: 255, count: width * height)
        context.render(output, toBitmap: &pixels, rowBytes: width, bounds: extent, format: .L8, colorSpace: nil)

        // Core Image adds its own margin; find the symbol (its finder patterns touch all three
        // corners) and re-pad it with our quiet zone.
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where pixels[y * width + x] < 128 {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }

        guard maxX >= minX, maxY >= minY else {
            return nil
        }

        let symbol = maxX - minX + 1
        let size = symbol + 2 * quietZone
        var modules = [Bool](repeating: false, count: size * size)
        for y in 0..<(maxY - minY + 1) {
            for x in 0..<symbol where pixels[(minY + y) * width + minX + x] < 128 {
                modules[(y + quietZone) * size + x + quietZone] = true
            }
        }

        return QRMatrix(size: size, modules: modules)
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
