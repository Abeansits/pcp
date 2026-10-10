import os

/// Unified logging. Clipboard contents are never logged.
enum Log {
    static let app = Logger(subsystem: "PCP", category: "app")
    static let sync = Logger(subsystem: "PCP", category: "sync")
}
