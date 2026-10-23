import Foundation
import PEACore

enum SecretHandling: String, CaseIterable, Identifiable {
    /// Keep in memory for `secretTTL` seconds; never written to disk or synced.
    case keepBriefly
    /// Drop it entirely.
    case neverStore
    /// Treat like any other text.
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .keepBriefly: "Keep briefly in memory, never save or sync"
        case .neverStore: "Never store"
        case .off: "Treat as normal text"
        }
    }
}

/// User settings, backed by UserDefaults.
@MainActor
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    @Published var historyLimit: Int { didSet { defaults.set(historyLimit, forKey: Key.historyLimit) } }
    @Published var pasteOrder: PasteOrder { didSet { defaults.set(pasteOrder.rawValue, forKey: Key.pasteOrder) } }
    @Published var pasteOnSelect: Bool { didSet { defaults.set(pasteOnSelect, forKey: Key.pasteOnSelect) } }
    @Published var syncEnabled: Bool { didSet { defaults.set(syncEnabled, forKey: Key.syncEnabled) } }
    /// 0 = keep until evicted by `historyLimit`.
    @Published var forgetAfterDays: Int { didSet { defaults.set(forgetAfterDays, forKey: Key.forgetAfterDays) } }
    @Published var secretHandling: SecretHandling { didSet { defaults.set(secretHandling.rawValue, forKey: Key.secretHandling) } }
    @Published var secretTTL: TimeInterval { didSet { defaults.set(secretTTL, forKey: Key.secretTTL) } }
    @Published var ignoredApps: [String] { didSet { defaults.set(ignoredApps, forKey: Key.ignoredApps) } }
    @Published var recordingPaused: Bool { didSet { defaults.set(recordingPaused, forKey: Key.recordingPaused) } }
    @Published var historyShortcut: AppShortcut { didSet { store(historyShortcut, key: Key.historyShortcut) } }
    @Published var pasteShortcut: AppShortcut { didSet { store(pasteShortcut, key: Key.pasteShortcut) } }
    /// True while Settings is waiting for a new shortcut. Not saved.
    @Published var isCapturingShortcut = false
    var didPromptForAccessibility: Bool {
        get { defaults.bool(forKey: Key.didPromptForAccessibility) }
        set { defaults.set(newValue, forKey: Key.didPromptForAccessibility) }
    }

    private enum Key {
        static let historyLimit = "historyLimit"
        static let pasteOrder = "pasteOrder"
        static let pasteOnSelect = "pasteOnSelect"
        static let syncEnabled = "syncEnabled"
        static let forgetAfterDays = "forgetAfterDays"
        static let secretHandling = "secretHandling"
        static let secretTTL = "secretTTL"
        static let ignoredApps = "ignoredApps"
        static let recordingPaused = "recordingPaused"
        static let didPromptForAccessibility = "didPromptForAccessibility"
        static let historyShortcut = "historyShortcut"
        static let pasteShortcut = "pasteShortcut"
    }

    private func store(_ shortcut: AppShortcut, key: String) {
        defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
    }

    private static func loadShortcut(_ key: String, from defaults: UserDefaults, fallback: AppShortcut) -> AppShortcut {
        guard let data = defaults.data(forKey: key),
              let shortcut = try? JSONDecoder().decode(AppShortcut.self, from: data),
              !shortcut.key.isEmpty
        else { return fallback }
        return shortcut
    }

    private init() {
        defaults.register(defaults: [
            Key.historyLimit: ClipHistory.defaultCapacity,
            Key.pasteOrder: PasteOrder.firstInFirstOut.rawValue,
            Key.pasteOnSelect: true,
            Key.syncEnabled: true,
            Key.forgetAfterDays: 0,
            Key.secretHandling: SecretHandling.keepBriefly.rawValue,
            Key.secretTTL: 60.0,
            Key.ignoredApps: SecretDetector.defaultIgnoredApps,
            Key.recordingPaused: false,
        ])
        historyLimit = defaults.integer(forKey: Key.historyLimit)
        pasteOrder = PasteOrder(rawValue: defaults.string(forKey: Key.pasteOrder) ?? "") ?? .firstInFirstOut
        pasteOnSelect = defaults.bool(forKey: Key.pasteOnSelect)
        syncEnabled = defaults.bool(forKey: Key.syncEnabled)
        forgetAfterDays = defaults.integer(forKey: Key.forgetAfterDays)
        secretHandling = SecretHandling(rawValue: defaults.string(forKey: Key.secretHandling) ?? "") ?? .keepBriefly
        secretTTL = defaults.double(forKey: Key.secretTTL)
        ignoredApps = defaults.stringArray(forKey: Key.ignoredApps) ?? SecretDetector.defaultIgnoredApps
        recordingPaused = defaults.bool(forKey: Key.recordingPaused)
        historyShortcut = Self.loadShortcut(Key.historyShortcut, from: defaults, fallback: .showHistory)
        pasteShortcut = Self.loadShortcut(Key.pasteShortcut, from: defaults, fallback: .pasteNext)
    }
}
