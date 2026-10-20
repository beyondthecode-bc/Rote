import SwiftUI

struct GeneralSettingsTab: View {
    @Environment(AppContainer.self) private var container
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?
    @State private var launchNeedsApproval = false

    var body: some View {
        @Bindable var settings = container.settings
        Form {
            Section {
                Toggle(l("settings.launchAtLogin"), isOn: launchAtLoginBinding)
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
                if launchNeedsApproval {
                    Button(l("permission.open")) { LaunchAtLogin.openSystemSettings() }
                }
                Toggle(l("settings.checkUpdatesOnLaunch"), isOn: $settings.checkUpdatesOnLaunch)
                Text(l("settings.updatesHint")).font(.caption).foregroundStyle(.secondary)
            }
            Section(l("settings.language")) {
                LanguagePicker()
                Text(l("settings.language.note")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    /// Calls SMAppService once per click, then shows the real status. Writing the status back
    /// through an onChange would fire it again and make the opposite call (unregister after a
    /// failed register), which hides the error that explains the failure.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { enabled in
                do {
                    try LaunchAtLogin.set(enabled)
                    launchError = nil
                } catch {
                    launchError = error.localizedDescription
                }
                launchAtLogin = LaunchAtLogin.isEnabled
                launchNeedsApproval = enabled && LaunchAtLogin.needsApproval
            }
        )
    }
}
