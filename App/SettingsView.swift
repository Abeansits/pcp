import AppKit
import PCPCore
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var sync: CloudSync
    let onClearHistory: () -> Void

    @State private var accessibilityGranted = Paster.canPostEvents
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Shortcuts") {
                LabeledContent("Show history & search", value: "⇧⌘C")
                LabeledContent("Paste & pop from stack", value: "⇧⌘V")
                LabeledContent("Pick item in history", value: "⌘1 … ⌘9, ↩")
            }

            Section("Pasting") {
                Picker("⇧⌘V pastes", selection: $prefs.pasteOrder) {
                    Text("In copy order (copy A B C → paste A B C)").tag(PasteOrder.firstInFirstOut)
                    Text("Newest first (copy A B C → paste C B A)").tag(PasteOrder.lastInFirstOut)
                }
                Toggle("Paste immediately when picking from history", isOn: $prefs.pasteOnSelect)
                HStack {
                    Label(
                        accessibilityGranted ? "Paste keystrokes allowed" : "Permission needed to paste keystrokes",
                        systemImage: accessibilityGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(accessibilityGranted ? .green : .orange)
                    Spacer()
                    if !accessibilityGranted {
                        Button("Open Settings…") { Paster.openAccessibilitySettings() }
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            accessibilityGranted = Paster.canPostEvents
        }
    }
}

private struct IgnoredAppsEditor: View {
    @Binding var bundleIDs: [String]
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Never record copies from")
            List(bundleIDs, id: \.self, selection: $selection) { id in
                Text(Self.displayName(for: id))
            }
            .frame(height: 110)
            HStack(spacing: 4) {
                Button { addApp() } label: { Image(systemName: "plus") }
                Button {
                    if let selection { bundleIDs.removeAll { $0 == selection } }
                    selection = nil
                } label: { Image(systemName: "minus") }
                .disabled(selection == nil)
            }
            .buttonStyle(.borderless)
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
