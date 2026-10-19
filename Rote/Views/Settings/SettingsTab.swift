import Foundation

/// Which Settings tab is selected; the popover footer sets it before opening Settings.
enum SettingsTab: String, CaseIterable {
    case general, coaching, overlay, apps, data, about

    static let storageKey = "settings.selectedTab"
}
