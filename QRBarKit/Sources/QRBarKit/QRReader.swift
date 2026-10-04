import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Finds QR codes (and other common barcodes) in images with Vision.
public enum QRReader {
    /// Images larger than this are scaled down before decoding; detection doesn't need more.
    public static let maxDecodeSize = 2048

    private static let symbologies: [BarcodeSymbology] = [
        .qr, .microQR, .dataMatrix, .aztec, .pdf417, .ean13, .upce, .code128,
    ]

    /// Decodes image file data (PNG, JPEG, HEIC, TIFF, …), honoring EXIF orientation, scaled down to
    /// ``maxDecodeSize`` and flattened onto white. Returns nil when the data isn't an image.
    public static func image(from data: Data) async -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            Log.read.error("Couldn't create an image source from \(data.count) bytes")
            return nil
        }

        return image(from: source)
    }

    /// Like ``image(from:)-(Data)`` but reads from a file.
    public static func image(contentsOf url: URL) async -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            Log.read.error("Couldn't create an image source from a .\(url.pathExtension, privacy: .public) file")
            return nil
        }

        return image(from: source)
    }

    /// Every distinct payload found in `image`, top to bottom, left to right.
    public static func decode(_ image: CGImage) async throws -> [String] {
        var request = DetectBarcodesRequest()
        request.symbologies = symbologies
        let start = ContinuousClock.now
        let observations: [BarcodeObservation]
        do {
            observations = try await request.perform(on: image)
        } catch {
            Log.read.error("Vision failed on a \(image.width)×\(image.height) image: \(String(describing: error), privacy: .public)")
            throw error
        }

        let symbologies = observations.map { String(describing: $0.symbology) }.joined(separator: ", ")
        Log.read.info("Vision found \(observations.count) code(s) [\(symbologies, privacy: .public)] in a \(image.width)×\(image.height) image in \(ContinuousClock.now - start, privacy: .public)")

        var seen = Set<String>()
        return observations
            .sorted { a, b in
                // Vision's normalized coordinates put the origin bottom-left.
                abs(a.boundingBox.origin.y - b.boundingBox.origin.y) > 0.02
                    ? a.boundingBox.origin.y > b.boundingBox.origin.y
                    : a.boundingBox.origin.x < b.boundingBox.origin.x
            }
            .compactMap(\.payloadString)
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func image(from source: CGImageSource) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else {
            Log.read.error("Image source has no images (type: \(CGImageSourceGetType(source) as String? ?? "unknown", privacy: .public))")
            return nil
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? maxDecodeSize
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? maxDecodeSize

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxDecodeSize, max(width, height)),
            kCGImageSourceShouldCacheImmediately: true,
        ]

        let type = CGImageSourceGetType(source) as String? ?? "unknown"
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            Log.read.error("Couldn't decode a \(width)×\(height) \(type, privacy: .public) image")
            return nil
        }

        Log.read.info("Loaded a \(width)×\(height) \(type, privacy: .public) image as \(image.width)×\(image.height), alpha \(image.alphaInfo.rawValue)")
        return flattenedOntoWhite(image)
    }

    /// Draws the image over white. A transparent PNG of a black code would otherwise read as all black.
    public static func flattenedOntoWhite(_ image: CGImage) -> CGImage? {
        guard image.alphaInfo != .none, image.alphaInfo != .noneSkipLast, image.alphaInfo != .noneSkipFirst else {
            return image
        }

        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: image.width,
                  height: image.height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
              )
        else {
            Log.read.error("Couldn't create a context to flatten a \(image.width)×\(image.height) image; decoding it as is")
            return image
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage() ?? image
    }
}
