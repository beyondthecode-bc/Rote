#if DEBUG
import Foundation
import RoteCore

/// A small Safari-like menu bar for the Debug menu's "Simulate overlay", for screenshots and
/// visual review of the sheet: four menus with coached and learned items, submenu items, a title
/// long enough to truncate, a disabled item, one without a shortcut and one Rote cannot draw.
/// Debug builds only.
enum OverlayFixture {
    static let bundleID = "com.apple.Safari"

    private static func item(_ path: [String], _ modifiers: Modifiers, _ key: String, enabled: Bool = true) -> MenuItemRecord {
        MenuItemRecord(bundleID: bundleID, path: path, shortcut: Shortcut(modifiers: modifiers, key: .character(key)), isEnabled: enabled)
    }

    private static func plain(_ path: [String]) -> MenuItemRecord {
        MenuItemRecord(bundleID: bundleID, path: path, shortcut: nil)
    }

    private static let newPrivateWindow = item(["File", "New Private Window"], [.shift, .command], "N")
    private static let pasteAndMatchStyle = item(["Edit", "Paste and Match Style"], [.option, .shift, .command], "V")
    private static let findNext = item(["Edit", "Find", "Find Next"], [.command], "G")
    private static let reloadPage = item(["View", "Reload Page"], [.command], "R")

    static let tree = MenuTree(
        bundleID: bundleID,
        appName: "Safari",
        menus: [
            MenuTree.Menu(title: "Safari", isAppleMenu: false, items: [
                plain(["Safari", "About Safari"]),
                item(["Safari", "Settings…"], [.command], ","),
                item(["Safari", "Hide Safari"], [.command], "H"),
                item(["Safari", "Hide Others"], [.option, .command], "H"),
                item(["Safari", "Quit Safari"], [.command], "Q"),
            ]),
            MenuTree.Menu(title: "File", isAppleMenu: false, items: [
                item(["File", "New Window"], [.command], "N"),
                newPrivateWindow,
                item(["File", "New Tab"], [.command], "T"),
                item(["File", "Open Location…"], [.command], "L"),
                item(["File", "Close Tab"], [.command], "W"),
                item(["File", "Reopen Last Closed Tab"], [.shift, .command], "T", enabled: false),
                plain(["File", "Export as PDF…"]),
            ]),
            MenuTree.Menu(title: "Edit", isAppleMenu: false, items: [
                item(["Edit", "Undo"], [.command], "Z"),
                item(["Edit", "Redo"], [.shift, .command], "Z"),
                item(["Edit", "Copy"], [.command], "C"),
                item(["Edit", "Paste"], [.command], "V"),
                pasteAndMatchStyle,
                item(["Edit", "Find", "Find…"], [.command], "F"),
                findNext,
                item(["Edit", "Find", "Find Previous"], [.shift, .command], "G"),
                MenuItemRecord(bundleID: bundleID, path: ["Edit", "Start Dictation…"], shortcut: nil, hasUnrenderableShortcut: true),
            ]),
            MenuTree.Menu(title: "View", isAppleMenu: false, items: [
                item(["View", "Show All Tabs"], [.shift, .command], "\\"),
                reloadPage,
                item(["View", "Show Reader and Hide Distracting Page Elements While You Read"], [.shift, .command], "R"),
                item(["View", "Zoom In"], [.command], "+"),
                item(["View", "Zoom Out"], [.command], "-"),
                item(["View", "Enter Full Screen"], [.control, .command], "F"),
            ]),
        ],
        scannedAt: Date(),
        isPartial: false
    )

    static let coaching: Set<String> = [reloadPage.identity, pasteAndMatchStyle.identity]
    static let learned: Set<String> = [newPrivateWindow.identity, findNext.identity]
}
#endif
