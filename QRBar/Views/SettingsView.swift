import AppKit
import SwiftUI

/// Settings, shown in place inside the popover. Back (or Esc) returns to the tabs.
struct SettingsView: View {
    @Environment(AppModel.self) private var app

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        @Bindable var loginItem = app.loginItem
        @Bindable var create = app.create

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button("Back", systemImage: "chevron.left") {
                    app.page = .main
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Back (Esc)")

                Text("Settings")
                    .font(.title3.weight(.semibold))
                    .accessibilityAddTraits(.isHeader)
            }
            .padding([.horizontal, .top], 14)

            Form {
                Section("General") {
                    Toggle(isOn: $loginItem.isEnabled) {
                        Text("Launch at login")
                        Text(loginItem.description)
                    }
                    .disabled(!loginItem.isAvailable)

                    if loginItem.needsApproval {
                        Button("Open Login Items Settings…", action: loginItem.openSystemSettings)
                    }
                }

                Section("Export") {
                    Picker(selection: $create.dragFormat) {
                        formatOptions
                    } label: {
                        Text("Drag out as")
                        Text("The file you get when dragging the code into a folder or app")
                    }

                    Picker(selection: $create.saveFormat) {
                        formatOptions
                    } label: {
                        Text("Copy and save as")
                        Text("The default for the Copy and Save buttons; their menus offer every format")
                    }
                }

                Section("About") {
                    LabeledContent("Version", value: version)
                    Text("QRBar works entirely offline. Nothing runs while the popover is closed.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            HStack {
                Spacer()
                Button("Quit QRBar") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q")
            }
            .padding([.horizontal, .bottom], 14)
        }
    }
}

private var formatOptions: some View {
    ForEach(ExportFormat.allCases) { format in
        Text(format.title).tag(format)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
        .frame(width: 340, height: 480)
}
