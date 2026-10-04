import AppKit
import CoreTransferable
import UniformTypeIdentifiers

/// Dragging the code out gives Finder a named file and gives apps its data, in the export's format.
extension QRExport: Transferable {
    nonisolated static var transferRepresentation: some TransferRepresentation {
        representation(for: .png)
        representation(for: .svg)
    }

    private nonisolated static func representation(for format: ExportFormat) -> some TransferRepresentation<QRExport> {
        DataRepresentation(exportedContentType: format.contentType) { export in
            guard let data = export.data(as: format) else {
                throw CocoaError(.fileWriteUnknown)
            }

            return data
        }
        .suggestedFileName { "\($0.fileName).\(format.fileExtension)" }
        .exportingCondition { $0.format == format }
    }
}

/// An image dropped on the Read tab: a file from Finder or image data from another app.
nonisolated struct DroppedImage: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            DroppedImage(data: try Data(contentsOf: received.file))
        }
        DataRepresentation(importedContentType: .image) { data in
            DroppedImage(data: data)
        }
    }
}

extension NSPasteboard {
    /// Puts a PNG on the clipboard, with TIFF for apps that only read that.
    func setPNG(_ png: Data) {
        clearContents()
        setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation {
            setData(tiff, forType: .tiff)
        }
    }

    /// Puts an SVG on the clipboard, as markup too for editors and text fields.
    func setSVG(_ svg: Data) {
        clearContents()
        setData(svg, forType: NSPasteboard.PasteboardType(UTType.svg.identifier))
        if let markup = String(data: svg, encoding: .utf8) {
            setString(markup, forType: .string)
        }
    }
}
