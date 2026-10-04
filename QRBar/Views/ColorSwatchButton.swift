import QRBarKit
import SwiftUI

/// A toolbar button showing a QR color that opens a palette to change it.
struct ColorSwatchButton: View {
    enum Kind {
        case code
        case background
    }

    let title: String
    let kind: Kind
    @Binding var color: QRColor
    let onReset: () -> Void

    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            swatch
                .frame(width: 16, height: 16)
        }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityValue(color.hex)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ColorPalette(color: $color, allowsTransparent: kind == .background, onReset: onReset)
                .padding(12)
        }
    }

    @ViewBuilder
    private var swatch: some View {
        switch kind {
        case .code:
            Image(systemName: "qrcode")
                .foregroundStyle(Color(cgColor: color.cgColor))
        case .background:
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(cgColor: color.cgColor))
                .background {
                    if !color.isOpaque {
                        Checkerboard(squareSize: 4)
                    }
                }
                .clipShape(.rect(cornerRadius: 3))
                .overlay {
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(.secondary.opacity(0.6), lineWidth: 0.5)
                }
        }
    }
}

private struct ColorPalette: View {
    private static let presets: [QRColor] = [
        "#000000", "#3A3A3C", "#8E8E93", "#FFFFFF", "#FFF8E7", "#1F2A44", "#0040DD", "#0A84FF",
        "#008080", "#1E7F3A", "#34C759", "#5E2CA5", "#AF52DE", "#C2185B", "#D70015", "#FF9500",
    ].compactMap(QRColor.init(hex:))

    @Binding var color: QRColor
    let allowsTransparent: Bool
    let onReset: () -> Void

    @State private var hex = ""

    private var isTransparent: Binding<Bool> {
        Binding {
            color.alpha == 0
        } set: { transparent in
            color = transparent ? .clear : .white
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 6), count: 8), spacing: 6) {
                ForEach(Self.presets, id: \.self) { preset in
                    Button {
                        color = preset
                    } label: {
                        Circle()
                            .fill(Color(cgColor: preset.cgColor))
                            .strokeBorder(.separator)
                            .overlay {
                                if preset == color {
                                    Image(systemName: "checkmark")
                                        .font(.caption.bold())
                                        .foregroundStyle(QRColor.contrastRatio(preset, .white) > 3 ? .white : .black)
                                }
                            }
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(preset.hex)
                    .accessibilityAddTraits(preset == color ? .isSelected : [])
                }
            }

            if allowsTransparent {
                Toggle("Transparent", isOn: isTransparent)
                    .help("Leave the background empty in copied, saved, and dragged images")
            }

            HStack {
                TextField("Hex", text: $hex)
                    .textFieldStyle(.roundedBorder)
                    .monospaced()
                    .frame(width: 90)
                    .onSubmit(applyHex)
                    .accessibilityLabel("Hex color")

                Spacer()

                Button("Reset to Black on White", action: onReset)
            }
        }
        .onAppear { hex = color.hex }
        .onChange(of: color) { hex = color.hex }
    }

    private func applyHex() {
        if let parsed = QRColor(hex: hex), allowsTransparent || parsed.isOpaque {
            color = parsed
        } else {
            hex = color.hex
        }
    }
}

/// Gray and white squares, the usual stand-in for "nothing here".
struct Checkerboard: View {
    var squareSize: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let columns = Int((size.width / squareSize).rounded(.up))
            let rows = Int((size.height / squareSize).rounded(.up))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    let square = CGRect(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize, width: squareSize, height: squareSize)
                    context.fill(Path(square), with: .color(Color(white: 0.85)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}
