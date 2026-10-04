import Foundation
import OSLog
import QRBarKit

/// Collects QRBar's log messages into plain text a tester can paste into a bug report.
///
/// The system keeps the app's info, notice, and error messages since it launched; debug messages
/// and anything logged before the last launch aren't available.
enum DiagnosticLog {
    /// Facts about this Mac and app that help explain a report.
    nonisolated static var systemSummary: [String] {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let process = ProcessInfo.processInfo
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = sysctlInt("sysctl.proc_translated") == 1 ? "x86_64 (Rosetta)" : "x86_64"
        #endif

        return [
            "QRBar \(version) (\(build))",
            "macOS \(process.operatingSystemVersionString)",
            "Mac: \(sysctlString("hw.model") ?? "unknown"), \(architecture), \(process.activeProcessorCount) cores, \(process.physicalMemory / 1_073_741_824) GB",
            "Locale: \(Locale.current.identifier), languages: \(Locale.preferredLanguages.prefix(3).joined(separator: ", "))",
            "Low Power Mode: \(process.isLowPowerModeEnabled ? "on" : "off"), thermal state: \(process.thermalState.rawValue)",
        ]
    }

    /// The header lines followed by every QRBar message since launch, oldest first.
    nonisolated static func report(header: [String]) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(matching: NSPredicate(format: "subsystem == %@", Log.subsystem))

            var lines = ["QRBar diagnostic log, \(Date.now.formatted(.iso8601))", ""] + header + [""]
            for case let entry as OSLogEntryLog in entries {
                let time = entry.date.formatted(.iso8601.time(includingFractionalSeconds: true))
                lines.append("\(time) [\(entry.category)] \(entry.level.name): \(entry.composedMessage)")
            }

            if lines.count == header.count + 3 {
                lines.append("(No messages logged since launch.)")
            }

            return lines.joined(separator: "\n") + "\n"
        }.value
    }

    private nonisolated static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }

        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }

        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }

    private nonisolated static func sysctlInt(_ name: String) -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? value : nil
    }
}

private extension OSLogEntryLog.Level {
    nonisolated var name: String {
        switch self {
        case .debug: "debug"
        case .info: "info"
        case .notice: "notice"
        case .error: "error"
        case .fault: "fault"
        default: "log"
        }
    }
}
