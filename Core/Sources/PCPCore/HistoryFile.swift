import Foundation

/// Reads and writes the history as JSON with atomic replacement, so a crash or
/// power loss mid-write never corrupts it.
public struct HistoryFile: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public func load() -> ClipHistory? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(ClipHistory.self, from: data)
    }

    public func save(_ history: ClipHistory) throws {
        let data = try Self.encoder.encode(history.persistable())
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
        // Owner-only: clipboard history is nobody else's business.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .millisecondsSince1970
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .millisecondsSince1970
        return d
    }()
}
