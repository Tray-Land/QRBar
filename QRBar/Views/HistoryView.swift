import QRBarKit
import SwiftUI

/// Recently made codes, shown in place inside the popover. Clicking one restores it on the Create
/// tab with its colors and error correction. Back (or Esc) returns to the tabs.
struct HistoryView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let history = app.history

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button("Back", systemImage: "chevron.left") {
                    app.page = .main
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Back (Esc)")

                Text("History")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Spacer()

                Button("Clear", action: history.clear)
                    .buttonStyle(.borderless)
                    .disabled(history.entries.isEmpty)
            }
            .padding(14)

            if history.entries.isEmpty {
                ContentUnavailableView(
                    "No History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Codes you copy, save, or leave open appear here.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List(history.entries) { entry in
                    Button {
                        app.restore(entry)
                    } label: {
                        HistoryRow(entry: entry)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Delete", systemImage: "trash") {
                            history.remove(entry)
                        }
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            history.remove(entry)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}

private struct HistoryRow: View {
    private static let thumbnailPixels = 96

    let entry: HistoryEntry

    private var thumbnail: CGImage? {
        QRCodec.encode(entry.text, correction: entry.correction).flatMap {
            QRCodec.render($0, scale: QRCodec.scale(for: $0, maxPixels: Self.thumbnailPixels), foreground: entry.foreground, background: entry.background)
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1)
                        .resizable()
                        .interpolation(.none)
                } else {
                    Image(systemName: "qrcode")
                        .resizable()
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(.rect(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.separator)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 4) {
                    Text(entry.date, format: .relative(presentation: .named))
                    Text("·")
                    Text(entry.correction.letter)
                        .monospaced()
                        .help("Error correction: \(entry.correction.title)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(entry.text)
        .accessibilityValue("Error correction \(entry.correction.title), \(entry.foreground.hex) on \(entry.background.hex)")
        .accessibilityHint("Restores this code")
    }
}

#Preview {
    HistoryView()
        .environment(AppModel())
        .frame(width: 340, height: 480)
}
