import Foundation
import RoteCore

/// Pure transformation from a recorded snapshot to the model the app uses (spec §5.1).
public enum MenuTreeBuilder {
    public static func build(_ snapshot: MenuSnapshot) -> MenuTree {
        var menus: [MenuTree.Menu] = []
        for (index, bar) in snapshot.barItems.enumerated() where bar.role == "AXMenuBarItem" {
            let isApple = index == 0 && (bar.title == "Apple" || bar.title.isEmpty)
            let menuTitle = isApple ? "Apple" : bar.title
            var items: [MenuItemRecord] = []
            for menu in bar.children where menu.role == "AXMenu" {
                collect(menu, path: [menuTitle], bundleID: snapshot.bundleID, into: &items)
            }
            menus.append(MenuTree.Menu(title: menuTitle, isAppleMenu: isApple, items: items, isComplete: index < snapshot.completeBarItemCount))
        }
        return MenuTree(bundleID: snapshot.bundleID, appName: snapshot.appName, menus: menus, scannedAt: snapshot.takenAt, isPartial: snapshot.isPartial)
    }

    private static func collect(_ menu: AXMenuNode, path: [String], bundleID: String, into items: inout [MenuItemRecord]) {
        for node in menu.children where node.role == "AXMenuItem" {
            let title = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty { continue }                       // separator
            if let submenu = node.children.first(where: { $0.role == "AXMenu" }) {
                collect(submenu, path: path + [title], bundleID: bundleID, into: &items)
                continue
            }
            items.append(record(for: node, path: path + [title], bundleID: bundleID))
        }
    }

    /// `path` ends with the item's own title, which is also its display title.
    static func record(for node: AXMenuNode, path: [String], bundleID: String) -> MenuItemRecord {
        let decoded = ShortcutDecoding.decode(cmdChar: node.cmdChar, modifierMask: node.cmdModifiers, virtualKey: node.cmdVirtualKey, glyph: node.cmdGlyph)
        switch decoded {
        case .none:
            return MenuItemRecord(bundleID: bundleID, path: path, shortcut: nil, isEnabled: node.isEnabled)
        case .shortcut(let shortcut):
            return MenuItemRecord(bundleID: bundleID, path: path, shortcut: shortcut, isEnabled: node.isEnabled)
        case .unrenderable:
            return MenuItemRecord(bundleID: bundleID, path: path, shortcut: nil, hasUnrenderableShortcut: true, isEnabled: node.isEnabled)
        }
    }
}
