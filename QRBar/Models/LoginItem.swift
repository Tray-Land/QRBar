import Observation
import ServiceManagement

/// "Launch at login" through `SMAppService`. The user has the final say in System Settings, so
/// the status is re-read whenever the popover opens.
@Observable
final class LoginItem {
    private(set) var status: SMAppService.Status = SMAppService.mainApp.status
    private(set) var errorMessage: String?

    var isEnabled: Bool {
        get { status == .enabled || status == .requiresApproval }
        set { setEnabled(newValue) }
    }

    var needsApproval: Bool { status == .requiresApproval }

    var isAvailable: Bool { status != .notFound }

    var description: String {
        if let errorMessage {
            return errorMessage
        }

        return switch status {
        case .requiresApproval: "Allow QRBar in System Settings › General › Login Items."
        case .notFound: "Not available for this copy of the app. Move it to Applications."
        default: "Keep QRBar in the menu bar after you log in."
        }
    }

    func refresh() {
        status = SMAppService.mainApp.status
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Couldn't change this: \(error.localizedDescription)"
        }

        refresh()
    }
}
