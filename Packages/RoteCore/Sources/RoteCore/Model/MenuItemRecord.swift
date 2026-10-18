import Foundation

/// Stable identity for a menu item across launches and dynamic titles.
public enum MenuItemIdentity {
    /// Strips quoted substrings ("…", '…', “…”, ‘…’), collapses whitespace, trims.
    /// "Close Tab “Example”" and "Close Tab" normalize to the same string.
    public static func normalize(_ title: String) -> String {
        var text = title
        text = text.replacing(/"[^"]*"|'[^']*'|“[^”]*”|‘[^’]*’/, with: "")
        text = text.replacing(/\s+/, with: " ")
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func make(bundleID: String, path: [String]) -> String {
        bundleID + "|" + path.map(normalize).joined(separator: "›")
    }
}

/// One menu item of one app: where it lives, what it is called, and its shortcut.
public struct MenuItemRecord: Codable, Hashable, Sendable, Identifiable {
    public var bundleID: String
    /// Menu titles from the menu bar down to the item: ["Edit", "Find", "Find Next"].
    public var path: [String]
    public var shortcut: Shortcut?
    /// The item reports a key equivalent Rote cannot draw. Shown as "?", never coached.
    public var hasUnrenderableShortcut: Bool
    public var isEnabled: Bool

    public init(bundleID: String, path: [String], shortcut: Shortcut?, hasUnrenderableShortcut: Bool = false, isEnabled: Bool = true) {
        self.bundleID = bundleID
        self.path = path
        self.shortcut = shortcut
        self.hasUnrenderableShortcut = hasUnrenderableShortcut
        self.isEnabled = isEnabled
    }

    public var title: String { path.last ?? "" }
    public var menuTitle: String { path.first ?? "" }
    /// Submenu titles between the top-level menu and the item.
    public var parentPath: [String] { path.count > 2 ? Array(path[1..<(path.count - 1)]) : [] }
    public var identity: String { MenuItemIdentity.make(bundleID: bundleID, path: path) }
    public var id: String { identity }
    public var isCoachable: Bool { shortcut != nil && isEnabled }
}
