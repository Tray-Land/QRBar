import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import QRBarKit

@Suite("Encoding and decoding")
struct QRCodecTests {
    @Test(arguments: [
        ("https://github.com/TheJoeFin/Simple-QR-Code-Maker", QRErrorCorrection.low),
        ("Hello, world!", .medium),
        ("Ünïcödé ✓ 二维码", .quartile),
        ("WIFI:T:WPA;S:MyNetwork;P:secret;;", .high),
    ])
    func roundTripsThroughRenderedPixels(text: String, correction: QRErrorCorrection) async throws {
        let matrix = try #require(QRCodec.encode(text, correction: correction))
        let image = try #require(QRCodec.render(matrix, scale: QRCodec.scale(for: matrix, maxPixels: 400)))

        #expect(try await QRReader.decode(image) == [text])
    }

    @Test func higherErrorCorrectionMakesALargerCode() throws {
        let text = "https://example.com/some/fairly/long/path"
        let high = try #require(QRCodec.encode(text, correction: .high))
        let low = try #require(QRCodec.encode(text, correction: .low))
        #expect(high.size > low.size)
    }

    @Test func emptyOrTooLongTextHasNoCode() {
        #expect(QRCodec.encode("", correction: .medium) == nil)
        #expect(QRCodec.encode(String(repeating: "x", count: 5000), correction: .medium) == nil)
    }

    @Test func finderPatternsAreTopLeftTopRightAndBottomLeft() throws {
        let matrix = try #require(QRCodec.encode("orientation", correction: .medium))
        let near = QRCodec.quietZone
        let far = matrix.size - QRCodec.quietZone - 7

        #expect(Self.hasFinder(in: matrix, x: near, y: near))
        #expect(Self.hasFinder(in: matrix, x: far, y: near))
        #expect(Self.hasFinder(in: matrix, x: near, y: far))
        #expect(!Self.hasFinder(in: matrix, x: far, y: far))
        #expect(!matrix.isDark(x: 0, y: 0), "quiet zone is light")
    }

    /// The 7×7 finder: a dark ring, a light ring, and a dark 3×3 center.
    private static func hasFinder(in matrix: QRMatrix, x: Int, y: Int) -> Bool {
        (0..<7).allSatisfy { dy in
            (0..<7).allSatisfy { dx in
                let ring = max(abs(dx - 3), abs(dy - 3))
                return matrix.isDark(x: x + dx, y: y + dy) == (ring != 2)
            }
        }
    }

    @Test func scaleKeepsImageWithinLimit() throws {
        let matrix = try #require(QRCodec.encode("abc", correction: .medium))
        let scale = QRCodec.scale(for: matrix, maxPixels: 512)
        #expect((512 - matrix.size)...512 ~= matrix.size * scale)
    }

    @Test func customColorsAreUsedAndStillDecode() async throws {
        let navy = QRColor(red: 0x1F, green: 0x2A, blue: 0x44)
        let cream = QRColor(red: 0xFF, green: 0xF8, blue: 0xE7)
        let matrix = try #require(QRCodec.encode("colored", correction: .medium))
        let image = try #require(QRCodec.render(matrix, scale: 8, foreground: navy, background: cream))

        // The top-left pixel is in the quiet zone, so it's the background.
        let pixel = try #require(Self.firstPixel(of: image))
        #expect(pixel == [cream.red, cream.green, cream.blue])
        #expect(try await QRReader.decode(image) == ["colored"])
    }

    @Test func blankImageDecodesToNothing() async throws {
        let blank = try #require(Self.solidImage(width: 100, height: 100, gray: 1))
        #expect(try await QRReader.decode(blank).isEmpty)
    }

    @Test func pngDataLoadsBackAndDecodes() async throws {
        let matrix = try #require(QRCodec.encode("png", correction: .medium))
        let png = try #require(QRCodec.render(matrix, scale: 10).flatMap(QRCodec.pngData))
        let loaded = try #require(await QRReader.image(from: png))
        #expect(try await QRReader.decode(loaded) == ["png"])
    }

    @Test func svgRendersAndDecodes() async throws {
        let navy = QRColor(red: 0x1F, green: 0x2A, blue: 0x44)
        let matrix = try #require(QRCodec.encode("svg", correction: .medium))
        let svg = QRCodec.svg(matrix, pixels: 400, foreground: navy, background: .white)
        #expect(svg.contains("width=\"400\""))
        #expect(svg.contains("viewBox=\"0 0 \(matrix.size) \(matrix.size)\""))
        #expect(svg.contains("fill=\"#1F2A44\""))

        let image = try #require(NSImage(data: Data(svg.utf8)))
        var rect = CGRect(x: 0, y: 0, width: 400, height: 400)
        let rendered = try #require(image.cgImage(forProposedRect: &rect, context: nil, hints: nil))
        #expect(try await QRReader.decode(rendered) == ["svg"])
    }

    @Test func nonImageDataLoadsAsNil() async {
        #expect(await QRReader.image(from: Data("not an image".utf8)) == nil)
    }

    @Test func transparentCodeIsFlattenedOntoWhite() async throws {
        // A black code on a fully transparent background, as many web QR generators export.
        let matrix = try #require(QRCodec.encode("transparent", correction: .medium))
        let scale = 8
        let width = matrix.size * scale
        let context = try #require(CGContext(
            data: nil, width: width, height: width, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        for y in 0..<matrix.size {
            for x in 0..<matrix.size where matrix.isDark(x: x, y: y) {
                context.fill(CGRect(x: x * scale, y: (matrix.size - 1 - y) * scale, width: scale, height: scale))
            }
        }

        let png = try #require(context.makeImage().flatMap(QRCodec.pngData))
        let loaded = try #require(await QRReader.image(from: png))
        #expect(loaded.alphaInfo == .noneSkipLast)
        #expect(try await QRReader.decode(loaded) == ["transparent"])
    }

    private static func firstPixel(of image: CGImage) -> [UInt8]? {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            return nil
        }

        // Draw so the image's top-left pixel lands on our single pixel.
        context.draw(image, in: CGRect(x: 0, y: 1 - image.height, width: image.width, height: image.height))
        return Array(pixel.prefix(3))
    }

    private static func solidImage(width: Int, height: Int, gray: CGFloat) -> CGImage? {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        context?.setFillColor(CGColor(gray: gray, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context?.makeImage()
    }
}

@Suite("Colors")
struct QRColorTests {
    @Test(arguments: [
        ("#1F2A44", QRColor(red: 0x1F, green: 0x2A, blue: 0x44)),
        ("ff8000", QRColor(red: 0xFF, green: 0x80, blue: 0x00)),
    ])
    func validHexParsesAndRoundTrips(hex: String, expected: QRColor) throws {
        let color = try #require(QRColor(hex: hex))
        #expect(color == expected)
        #expect(QRColor(hex: color.hex) == color)
    }

    @Test(arguments: ["", "#12345", "#GGGGGG", "#1234567", "+12345"])
    func invalidHexIsNil(hex: String) {
        #expect(QRColor(hex: hex) == nil)
    }

    @Test func contrastRatioMatchesWCAG() {
        #expect(abs(QRColor.contrastRatio(.black, .white) - 21) < 0.1)
        #expect(abs(QRColor.contrastRatio(.white, .white) - 1) < 0.001)
        #expect(QRColor.contrastRatio(QRColor(red: 200, green: 200, blue: 200), .white) < QRCodec.minReadableContrast)
    }
}

@Suite("Scan results and file names")
struct ScanResultTests {
    @Test(arguments: ["https://example.com", "HTTP://EXAMPLE.COM/a", "mailto:a@b.c", "tel:+15551234", "geo:47.6,-122.3"])
    func launchableTextHasLink(text: String) {
        #expect(ScanResult(text: text).link != nil)
    }

    @Test(arguments: ["Hello", "javascript:alert(1)", "file:///etc/passwd", "WIFI:T:WPA;S:x;P:y;;", ""])
    func otherTextHasNoLink(text: String) {
        #expect(ScanResult(text: text).link == nil)
    }

    @Test func fileNamesAreShortAndSafe() {
        #expect(QRFileName.suggested(for: "https://example.com/a b?c") == "QR example.com-a-b-c")
        #expect(QRFileName.suggested(for: "   ") == "QR code")
        #expect(QRFileName.suggested(for: "///") == "QR code")
        #expect(QRFileName.suggested(for: String(repeating: "a", count: 100)).count == 43)
    }
}
