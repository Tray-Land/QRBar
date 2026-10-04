import OSLog

/// Loggers for each part of the app, under one subsystem so Settings can copy them all.
///
/// Use `.info` or higher for anything worth seeing in a copied report: debug messages aren't kept
/// where the app can read them back. Strings are private by default and show as `<private>` in
/// reports, so mark only non-sensitive values `.public` and never log the text people encode or scan.
public enum Log {
    public static let subsystem = "com.joefinapps.QRBar"

    public static let app = Logger(subsystem: subsystem, category: "App")
    public static let create = Logger(subsystem: subsystem, category: "Create")
    public static let read = Logger(subsystem: subsystem, category: "Read")
    public static let export = Logger(subsystem: subsystem, category: "Export")
    public static let history = Logger(subsystem: subsystem, category: "History")
    public static let settings = Logger(subsystem: subsystem, category: "Settings")
    static let codec = Logger(subsystem: subsystem, category: "Codec")
}
