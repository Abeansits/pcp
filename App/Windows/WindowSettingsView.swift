import AppKit
import PEACore
import SwiftUI

struct WindowSettingsView: View {
    @ObservedObject var prefs: Preferences

    @State private var trusted = WindowManager.isTrusted

    var body: some View {
        Form {
            Section {
                Toggle("Window shortcuts", isOn: $prefs.windowShortcutsEnabled)
                LabeledContent("Moving windows") {
                    HStack(spacing: 6) {
                        Image(systemName: trusted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(trusted ? .green : .orange)
                        Text(trusted ? "Allowed" : "Needs permission")
                        if !trusted {
                            Button("Allow…") {
                                WindowManager.requestAccess()
                                Paster.openAccessibilitySettings()
                            }
                        }
                    }
                }
            } footer: {
                Text("Moving another app's windows needs the Accessibility permission. The menu bar's Move Window menu works even with the shortcuts off.")
                    .foregroundStyle(.secondary)
            }

            ForEach(WindowShortcut.groups, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.shortcuts, id: \.action) { shortcut in
                        LabeledContent(shortcut.action.title) {
                            Text(shortcut.symbols)
                                .font(.body.monospaced())
                                .foregroundStyle(prefs.windowShortcutsEnabled ? .primary : .tertiary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            trusted = WindowManager.isTrusted
        }
    }
}
