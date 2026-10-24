import AppKit
import PEACore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// Settings, one toolbar tab per tool.
@MainActor
enum SettingsWindow {
    static func make(prefs: Preferences, sync: CloudSync, onClearHistory: @escaping () -> Void) -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(tab("Clipboard", symbol: "doc.on.clipboard",
                                ClipboardSettingsView(prefs: prefs, sync: sync, onClearHistory: onClearHistory)))
        tabs.addTabViewItem(tab("Windows", symbol: "rectangle.split.2x1", WindowSettingsView(prefs: prefs)))
        tabs.addTabViewItem(tab("General", symbol: "gearshape", GeneralSettingsView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private static func tab(_ label: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        // The window takes each tab's size when you switch to it.
        host.sizingOptions = .preferredContentSize
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

struct ClipboardSettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var sync: CloudSync
    let onClearHistory: () -> Void

    @State private var accessibilityGranted = Paster.canPostEvents

    var body: some View {
        Form {
            Section("Shortcuts") {
                ShortcutField(title: "Show history & search", shortcut: $prefs.historyShortcut, reserved: prefs.pasteShortcut) {
                    prefs.isCapturingShortcut = $0
                }
                ShortcutField(title: "Paste & pop from stack", shortcut: $prefs.pasteShortcut, reserved: prefs.historyShortcut) {
                    prefs.isCapturingShortcut = $0
                }
                LabeledContent("Paste with style") {
                    Text(prefs.pasteShortcut.addingOption() == prefs.pasteShortcut
                         ? "⌥↩ in the history panel"
                         : prefs.pasteShortcut.addingOption().symbols)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Pick item in history", value: "⌘1 … ⌘9, ↩")
                Text("Click a shortcut, then type a new one. It needs ⌘, ⌥, or ⌃.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Pasting") {
                Picker("\(prefs.pasteShortcut.symbols) pastes", selection: $prefs.pasteOrder) {
                    Text("Oldest first").tag(PasteOrder.firstInFirstOut)
                    Text("Newest first").tag(PasteOrder.lastInFirstOut)
                }
                Text(prefs.pasteOrder == .firstInFirstOut
                     ? "Copy A, B, C, then paste A, B, C."
                     : "Copy A, B, C, then paste C, B, A.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Paste immediately when picking from history", isOn: $prefs.pasteOnSelect)
                LabeledContent("Paste keystrokes") {
                    HStack(spacing: 6) {
                        Image(systemName: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(accessibilityGranted ? .green : .orange)
                        Text(accessibilityGranted ? "Allowed" : "Needs permission")
                        if !accessibilityGranted {
                            Button("Open Settings…") { Paster.openAccessibilitySettings() }
                        }
                    }
                }
            }

            Section("History") {
                Stepper(value: $prefs.historyLimit, in: 50...10_000, step: 50) {
                    LabeledContent("Keep at most", value: "\(prefs.historyLimit) items")
                }
                Picker("Forget items after", selection: $prefs.forgetAfterDays) {
                    Text("Never").tag(0)
                    Text("1 day").tag(1)
                    Text("1 week").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                }
                Toggle("Pause recording", isOn: $prefs.recordingPaused)
                Button("Clear History…", role: .destructive, action: onClearHistory)
            }

            Section {
                Picker("Password-like text", selection: $prefs.secretHandling) {
                    ForEach(SecretHandling.allCases) { Text($0.title).tag($0) }
                }
                if prefs.secretHandling == .keepBriefly {
                    Picker("Forget it after", selection: $prefs.secretTTL) {
                        Text("30 seconds").tag(30.0)
                        Text("1 minute").tag(60.0)
                        Text("5 minutes").tag(300.0)
                    }
                }
                IgnoredAppsEditor(bundleIDs: $prefs.ignoredApps)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Copies that password managers mark as concealed are never recorded. Nothing leaves this Mac except your own iCloud sync, end-to-end encrypted. No analytics.")
                    .foregroundStyle(.secondary)
            }

            Section("iCloud") {
                Toggle("Sync history with my other Macs", isOn: $prefs.syncEnabled)
                LabeledContent("Status") {
                    HStack {
                        Text(sync.status.description).foregroundStyle(.secondary)
                        if prefs.syncEnabled {
                            Button("Sync Now") { sync.syncNow() }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            accessibilityGranted = Paster.canPostEvents
        }
    }
}

struct GeneralSettingsView: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            Log.app.error("Login item change failed: \(error.localizedDescription, privacy: .public)")
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            } footer: {
                Text("Turn this on after PEA is in its final folder. The login item points at that path.")
                    .foregroundStyle(.secondary)
            }
            Section("About") {
                LabeledContent("PEA", value: "Personal Everything App")
                LabeledContent("Version", value: version)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 260)
    }
}

private struct IgnoredAppsEditor: View {
    @Binding var bundleIDs: [String]
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Never record copies from")
            List(bundleIDs, id: \.self, selection: $selection) { id in
                let name = Self.displayName(for: id)
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                    if name != id {
                        Text(id)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(height: 132)
            HStack(spacing: 8) {
                Button("Add App…", action: addApp)
                Button("Remove") {
                    if let selection { bundleIDs.removeAll { $0 == selection } }
                    selection = nil
                }
                .disabled(selection == nil)
            }
            .controlSize(.small)
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            if let id = Bundle(url: url)?.bundleIdentifier, !bundleIDs.contains(id) {
                bundleIDs.append(id)
            }
        }
    }

    private static func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }
}
