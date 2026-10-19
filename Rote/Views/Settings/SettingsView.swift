import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsTab.storageKey) private var selectedTab: String = SettingsTab.general.rawValue

    private var selection: Binding<SettingsTab> {
        Binding(
            get: { SettingsTab(rawValue: selectedTab) ?? .general },
            set: { selectedTab = $0.rawValue }
        )
    }

    var body: some View {
        TabView(selection: selection) {
            GeneralSettingsTab()
                .tabItem { Label(l("settings.general"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            CoachingSettingsTab()
                .tabItem { Label(l("settings.coaching"), systemImage: "graduationcap") }
                .tag(SettingsTab.coaching)
            OverlaySettingsTab()
                .tabItem { Label(l("settings.overlay"), systemImage: "rectangle.on.rectangle") }
                .tag(SettingsTab.overlay)
            AppsSettingsTab()
                .tabItem { Label(l("settings.apps"), systemImage: "app.badge") }
                .tag(SettingsTab.apps)
            DataSettingsTab()
                .tabItem { Label(l("settings.data"), systemImage: "internaldrive") }
                .tag(SettingsTab.data)
            AboutView()
                .tabItem { Label(l("about.title"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(width: DesignTokens.settingsWidth)
    }
}
