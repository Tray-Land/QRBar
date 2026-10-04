import SwiftUI

/// The popover's content: the Create and Read tabs, History, or Settings.
struct PopoverView: View {
    static let size = CGSize(width: 340, height: 480)

    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            switch app.page {
            case .main:
                MainView()
            case .settings:
                SettingsView()
            case .history:
                HistoryView()
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

private struct MainView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app

        VStack(spacing: 12) {
            HStack {
                Picker("Mode", selection: $app.tab) {
                    Label("Create", systemImage: "qrcode").tag(AppModel.Tab.create)
                    Label("Read", systemImage: "qrcode.viewfinder").tag(AppModel.Tab.read)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()

                Button("History", systemImage: "clock.arrow.circlepath") {
                    app.page = .history
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut("y")
                .help("History (⌘Y)")

                Button("Settings", systemImage: "gearshape") {
                    app.page = .settings
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(",")
                .help("Settings (⌘,)")
            }

            switch app.tab {
            case .create:
                CreateView()
            case .read:
                ReadView()
            }
        }
        .padding(14)
    }
}

#Preview {
    PopoverView()
        .environment(AppModel())
}
