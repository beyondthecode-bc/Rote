import Foundation

/// The scanned menu bar of one app. Submenu items are flattened into their
/// top-level menu with `parentPath` describing where they came from.
public struct MenuTree: Codable, Sendable, Equatable {
    public struct Menu: Codable, Sendable, Equatable, Identifiable {
        public var title: String
        public var isAppleMenu: Bool
        public var items: [MenuItemRecord]
        /// False when the scan stopped inside this menu, so `items` may lack some of its items.
        public var isComplete: Bool

        public init(title: String, isAppleMenu: Bool, items: [MenuItemRecord], isComplete: Bool = true) {
            self.title = title
            self.isAppleMenu = isAppleMenu
            self.items = items
            self.isComplete = isComplete
        }

        public var id: String { title }
    }

    public var bundleID: String
    public var appName: String
    public var menus: [Menu]
    public var scannedAt: Date
    /// True when the scan stopped early: it hit its time budget or a read failed.
    public var isPartial: Bool

    public init(bundleID: String, appName: String, menus: [Menu], scannedAt: Date, isPartial: Bool) {
        self.bundleID = bundleID
        self.appName = appName
        self.menus = menus
        self.scannedAt = scannedAt
        self.isPartial = isPartial
    }

    public var allItems: [MenuItemRecord] { menus.flatMap(\.items) }

    /// The tree to cache after this scan, given the cached tree it would replace (spec §5.1).
    /// A complete scan, or one with nothing cached, stands as is. A partial one keeps the menus
    /// it read in full, then every other cached menu, so a busy app never loses menus the cache
    /// already had. The result stays partial, so the next activation rescans.
    public func merged(over previous: MenuTree?) -> MenuTree {
        guard isPartial, let previous, previous.bundleID == bundleID else { return self }
        let fresh = menus.filter(\.isComplete)
        let freshTitles = Set(fresh.map(\.title))
        let cached = previous.menus.filter { !freshTitles.contains($0.title) }
        let cachedTitles = Set(cached.map(\.title))
        let cutShort = menus.filter { !$0.isComplete && !freshTitles.contains($0.title) && !cachedTitles.contains($0.title) }
        var merged = self
        merged.menus = fresh + cached + cutShort
        return merged
    }

    public var shortcutCount: Int { allItems.filter { $0.shortcut != nil }.count }

    /// First enabled item bound to `shortcut`, in menu order (the order AppKit fires).
    public func item(for shortcut: Shortcut) -> MenuItemRecord? {
        menus.lazy.flatMap(\.items).first { $0.isEnabled && $0.shortcut == shortcut }
    }

    public func contains(identity: String) -> Bool {
        menus.contains { $0.items.contains { $0.identity == identity } }
    }
}
