import Foundation

/// Where System Settings lists the apps with Accessibility access. Through macOS 26 the list is
/// Privacy & Security › Accessibility. macOS 27 calls it Privacy & Security › Device Control and
/// Data Access, while the sidebar's own Accessibility item is the VoiceOver and Zoom pane, so a
/// text that names the list has a second key, ending in `.macOS27`, with System Settings' new name.
/// The settings URL that opens the list is the same on every version.
enum PermissionPane {
    /// The running system's major version: 14 on Sonoma, 27 on macOS 27.
    static var systemMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// `key` before macOS 27, `key` + ".macOS27" from macOS 27 on.
    static func key(_ key: String, majorVersion: Int = systemMajorVersion) -> String {
        majorVersion >= 27 ? key + ".macOS27" : key
    }
}
