import ServiceManagement
import SwiftUI

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
