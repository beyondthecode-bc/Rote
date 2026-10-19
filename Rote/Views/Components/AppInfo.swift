import AppKit

/// Bundle ID → display name and icon, cached for the popover and HUD.
@MainActor
enum AppInfo {
    struct Info {
        let name: String
        let icon: NSImage
    }

    private static var cache: [String: Info] = [:]

    static func resolve(_ bundleID: String) -> Info {
        if let cached = cache[bundleID] { return cached }
        let info: Info
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first, let icon = running.icon {
            info = Info(name: running.localizedName ?? bundleID, icon: icon)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let bundle = Bundle(url: url)
            let name = (bundle?.infoDictionary?["CFBundleDisplayName"] as? String)
                ?? (bundle?.infoDictionary?["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent
            info = Info(name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        } else {
            info = Info(name: bundleID, icon: NSWorkspace.shared.icon(for: .applicationBundle))
        }
        cache[bundleID] = info
        return info
    }
}
