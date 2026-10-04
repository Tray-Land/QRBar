import UniformTypeIdentifiers

/// The file types a code can be copied, saved, or dragged out as.
nonisolated enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case png
    case svg

    var id: Self { self }

    var title: String {
        switch self {
        case .png: "PNG"
        case .svg: "SVG"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .svg: .svg
        }
    }

    var fileExtension: String { rawValue }
}
