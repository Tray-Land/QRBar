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
            ColorPalette(color: $color, onReset: onReset)
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
                .strokeBorder(.secondary.opacity(0.6), lineWidth: 0.5)
        }
    }
}

private struct ColorPalette: View {
    private static let presets: [QRColor] = [
        "#000000", "#3A3A3C", "#8E8E93", "#FFFFFF", "#FFF8E7", "#1F2A44", "#0040DD", "#0A84FF",
        "#008080", "#1E7F3A", "#34C759", "#5E2CA5", "#AF52DE", "#C2185B", "#D70015", "#FF9500",
    ].compactMap(QRColor.init(hex:))

    @Binding var color: QRColor
    let onReset: () -> Void

    @State private var hex = ""

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
        if let parsed = QRColor(hex: hex) {
            color = parsed
        } else {
            hex = color.hex
        }
    }
}
