import Foundation

/// The scanned menu bar of one app. Submenu items are flattened into their
/// top-level menu with `parentPath` describing where they came from.
public struct MenuTree: Codable, Sendable, Equatable {
    public struct Menu: Codable, Sendable, Equatable, Identifiable {
        public var title: String
        public var isAppleMenu: Bool
        public var items: [MenuItemRecord]

        public init(title: String, isAppleMenu: Bool, items: [MenuItemRecord]) {
            self.title = title
            self.isAppleMenu = isAppleMenu
            self.items = items
        }

        public var id: String { title }
    }

    public var bundleID: String
    public var appName: String
    public var menus: [Menu]
    public var scannedAt: Date
    /// True when the scan hit its time budget before finishing.
    public var isPartial: Bool

    public init(bundleID: String, appName: String, menus: [Menu], scannedAt: Date, isPartial: Bool) {
        self.bundleID = bundleID
        self.appName = appName
        self.menus = menus
        self.scannedAt = scannedAt
        self.isPartial = isPartial
    }

    public var allItems: [MenuItemRecord] { menus.flatMap(\.items) }

    public var shortcutCount: Int { allItems.filter { $0.shortcut != nil }.count }

    /// First enabled item bound to `shortcut`, in menu order.
    public func item(for shortcut: Shortcut) -> MenuItemRecord? {
        allItems.first { $0.isEnabled && $0.shortcut == shortcut }
    }

    public func contains(identity: String) -> Bool {
        allItems.contains { $0.identity == identity }
    }
}
