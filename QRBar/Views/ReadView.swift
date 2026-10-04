import AppKit
import QRBarKit
import SwiftUI

/// Finds codes in a captured, pasted, opened, or dropped image.
struct ReadView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @State private var isDropTargeted = false

    var body: some View {
        let read = app.read

        VStack(spacing: 12) {
            dropZone
                .frame(height: 160)

            HStack(spacing: 8) {
                Button {
                    Task { await app.scanScreen() }
                } label: {
                    Label("Screen", systemImage: "rectangle.dashed")
                        .frame(maxWidth: .infinity)
                }
                .help("Select part of the screen and read the codes in it")

                Button {
                    Task { await read.readPasteboard() }
                } label: {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("v")
                .help("Read an image from the clipboard (⌘V)")

                Button {
                    Task { await app.openImageFile() }
                } label: {
                    Label("Open", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("o")
                .help("Open an image file (⌘O)")
            }
            .controlSize(.large)

            Group {
                if read.isReading {
                    ProgressView()
                        .controlSize(.small)
                } else if let message = read.message {
                    VStack(spacing: 8) {
                        Text(message)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if read.needsScreenPermission {
                            Button("Open Privacy Settings") {
                                openURL(ScreenCapture.privacySettingsURL)
                            }
                        }
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(read.results) { result in
                                ResultCard(result: result)
                            }
                        }
                    }
                    .scrollBounceBehavior(.basedOnSize)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var dropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quinary)
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isDropTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator),
                    style: StrokeStyle(lineWidth: isDropTargeted ? 2 : 1, dash: isDropTargeted ? [] : [5, 4])
                )

            if let image = app.read.sourceImage {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "photo.badge.arrow.down")
                        .font(.largeTitle)
                    Text("Drop an image or press ⌘V")
                }
                .foregroundStyle(.secondary)
            }
        }
        .dropDestination(for: DroppedImage.self) { items, _ in
            guard let image = items.first else {
                return false
            }

            Task { await app.read.read(imageData: image.data) }
            return true
        } isTargeted: {
            isDropTargeted = $0
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Image to read")
    }
}

private struct ResultCard: View {
    let result: ScanResult

    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(result.text)
                .textSelection(.enabled)
                .lineLimit(6)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                if let link = result.link {
                    Button("Open") {
                        openURL(link)
                    }
                    .help(link.absoluteString)
                }

                FlashButton("Copy Text", systemImage: "doc.on.doc", doneTitle: "Copied") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(result.text, forType: .string)
                    return true
                }
                .labelStyle(.titleOnly)

                Button("Make New Code") {
                    app.makeCode(from: result.text)
                }
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quinary, in: .rect(cornerRadius: 8))
    }
}

#Preview {
    ReadView()
        .environment(AppModel())
        .padding()
        .frame(width: 340, height: 440)
}
