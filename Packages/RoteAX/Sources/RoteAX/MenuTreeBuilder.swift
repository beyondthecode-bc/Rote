import Foundation
import RoteCore

/// Pure transformation from a recorded snapshot to the model the app uses (spec §5.1).
public enum MenuTreeBuilder {
    /// Longest path (menu titles down to the item) a record may have. `MenuScanner` already stops
    /// at its own depth cap; this one guards replayed snapshots, so `collect` cannot recurse
    /// without bound either (audit M3).
    static let maxDepth = 12
    /// Menu item nodes visited in one build, over every menu. Past it the tree is partial.
    static let maxNodes = 5_000

    public static func build(_ snapshot: MenuSnapshot) -> MenuTree {
        var menus: [MenuTree.Menu] = []
        var partial = snapshot.isPartial
        var nodes = 0
        for (index, bar) in snapshot.barItems.enumerated() where bar.role == "AXMenuBarItem" {
            let barTitle = MenuTitleSanitizer.sanitize(bar.title)
            let isApple = index == 0 && (barTitle == "Apple" || barTitle.isEmpty)
            let menuTitle = isApple ? "Apple" : barTitle
            var items: [MenuItemRecord] = []
            var cutShort = false
            for menu in bar.children where menu.role == "AXMenu" {
                collect(menu, path: [menuTitle], bundleID: snapshot.bundleID, into: &items, nodes: &nodes, cutShort: &cutShort)
            }
            if cutShort { partial = true }
            menus.append(MenuTree.Menu(title: menuTitle, isAppleMenu: isApple, items: items, isComplete: index < snapshot.completeBarItemCount && !cutShort))
        }
        return MenuTree(bundleID: snapshot.bundleID, appName: snapshot.appName, menus: menus, scannedAt: snapshot.takenAt, isPartial: partial)
    }

    /// `cutShort` is set when the depth or node cap left items of this menu out.
    private static func collect(_ menu: AXMenuNode, path: [String], bundleID: String, into items: inout [MenuItemRecord], nodes: inout Int, cutShort: inout Bool) {
        guard path.count < maxDepth else { cutShort = true; return }
        for node in menu.children where node.role == "AXMenuItem" {
            guard nodes < maxNodes else { cutShort = true; return }
            nodes += 1
            let title = MenuTitleSanitizer.sanitize(node.title)
            if title.isEmpty { continue }                       // separator
            if let submenu = node.children.first(where: { $0.role == "AXMenu" }) {
                collect(submenu, path: path + [title], bundleID: bundleID, into: &items, nodes: &nodes, cutShort: &cutShort)
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
