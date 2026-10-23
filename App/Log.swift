import os

/// Unified logging. Clipboard contents are never logged.
enum Log {
    static let app = Logger(subsystem: "PEA", category: "app")
    static let sync = Logger(subsystem: "PEA", category: "sync")
}
