import AppKit
import QRBarKit
import SwiftUI

/// Text in, QR code out. The code can be recolored, copied, saved, or dragged anywhere.
struct CreateView: View {
    @Environment(AppModel.self) private var app
    @FocusState private var isTextFocused: Bool

    var body: some View {
        @Bindable var create = app.create

        VStack(spacing: 12) {
            TextField("Type text or paste a link", text: $create.text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .focused($isTextFocused)
                .accessibilityLabel("Text to encode")

            preview
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if create.hasLowContrast {
                Label("Low contrast: some scanners may not read this code", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                ColorSwatchButton(title: "Code color", kind: .code, color: $create.foreground, onReset: create.resetColors)
                ColorSwatchButton(title: "Background color", kind: .background, color: $create.background, onReset: create.resetColors)

                Menu {
                    Picker("Error correction", selection: $create.correction) {
                        ForEach(QRErrorCorrection.allCases) { level in
                            Text(level.title).tag(level)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(create.correction.letter)
                        .monospaced()
                }
                .fixedSize()
                .help("Error correction: \(create.correction.title). Higher levels survive more damage but make a denser code.")
                .accessibilityLabel("Error correction")
                .accessibilityValue(create.correction.title)

                Spacer()

                FlashButton(
                    "Copy as \(create.saveFormat.title)",
                    systemImage: "doc.on.doc",
                    doneTitle: "Copied",
                    alternatives: ExportFormat.allCases.map { format in
                        .init(title: "Copy as \(format.title)") { app.copyImage(as: format) }
                    }
                ) {
                    app.copyImage(as: create.saveFormat)
                }

                FlashButton(
                    "Save as \(create.saveFormat.title)…",
                    systemImage: "square.and.arrow.down",
                    doneTitle: "Saved",
                    alternatives: ExportFormat.allCases.map { format in
                        .init(title: "Save as \(format.title)…") { await app.saveImage(as: format) }
                    }
                ) {
                    await app.saveImage(as: create.saveFormat)
                }
            }
            .background {
                // Menus don't reliably take keyboard shortcuts, so hidden buttons carry them.
                Group {
                    Button("Copy") { _ = app.copyImage(as: create.saveFormat) }
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                    Button("Save") { Task { await app.saveImage(as: create.saveFormat) } }
                        .keyboardShortcut("s")
                }
                .hidden()
                .accessibilityHidden(true)
            }
            .labelStyle(.iconOnly)
            .controlSize(.large)
            .disabled(create.matrix == nil)
        }
        .onAppear { isTextFocused = true }
        .onChange(of: app.showCount) { isTextFocused = true }
    }

    @ViewBuilder
    private var preview: some View {
        let create = app.create
        if let image = create.previewImage, let export = create.export {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.none)
                .aspectRatio(1, contentMode: .fit)
                .background {
                    if !create.background.isOpaque {
                        Checkerboard()
                    }
                }
                .clipShape(.rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.separator)
                }
                .draggable(export)
                .help("Drag into a folder, chat, or document")
                .accessibilityLabel("QR code")
                .accessibilityValue(create.text)
        } else if create.isTooLong {
            ContentUnavailableView(
                "Too Much Text",
                systemImage: "exclamationmark.triangle",
                description: Text("Shorten it or lower the error correction.")
            )
        } else {
            Image(systemName: "qrcode")
                .font(.system(size: 96, weight: .ultraLight))
                .foregroundStyle(.quaternary)
                .accessibilityHidden(true)
        }
    }
}

#Preview {
    CreateView()
        .environment(AppModel())
        .padding()
        .frame(width: 340, height: 440)
}
