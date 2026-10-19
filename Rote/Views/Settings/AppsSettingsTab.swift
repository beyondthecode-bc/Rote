import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppsSettingsTab: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        @Bindable var settings = container.settings
        Form {
            Section(l("settings.excluded")) {
                AppListEditor(bundleIDs: $settings.excludedBundleIDs)
            }
            Section(l("settings.paused")) {
                AppListEditor(bundleIDs: $settings.pausedBundleIDs)
            }
        }
        .formStyle(.grouped)
    }
}

/// A list of apps with an "Add App" menu (running apps or a file picker).
struct AppListEditor: View {
    @Binding var bundleIDs: [String]

    var body: some View {
        ForEach(bundleIDs, id: \.self) { bundleID in
            let info = AppInfo.resolve(bundleID)
            HStack {
                Image(nsImage: info.icon).resizable().frame(width: 16, height: 16)
                Text(info.name)
                Spacer()
                Button(l("general.remove")) { bundleIDs.removeAll { $0 == bundleID } }
                    .buttonStyle(.borderless)
            }
        }
        Menu(l("settings.addApp")) {
            Section(l("settings.runningApps")) {
                ForEach(runningApps, id: \.processIdentifier) { app in
                    if let bundleID = app.bundleIdentifier {
                        Button(app.localizedName ?? bundleID) { add(bundleID) }
                    }
                }
            }
            Button(l("settings.chooseApp")) { chooseFromDisk() }
        }
        .fixedSize()
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != Bundle.main.bundleIdentifier }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func add(_ bundleID: String) {
        if !bundleIDs.contains(bundleID) { bundleIDs.append(bundleID) }
    }

    private func chooseFromDisk() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        add(bundleID)
    }
}
