import Foundation

/// One Accessibility element of a menu tree, with the attributes Rote reads.
/// Recorded by `MenuScanner`, replayed from JSON in tests and the Debug export.
public struct AXMenuNode: Codable, Sendable, Equatable {
    public var role: String
    public var title: String
    public var isEnabled: Bool
    public var cmdChar: String?
    public var cmdModifiers: Int?
    public var cmdVirtualKey: Int?
    public var cmdGlyph: Int?
    public var children: [AXMenuNode]

    public init(role: String, title: String, isEnabled: Bool, cmdChar: String? = nil, cmdModifiers: Int? = nil, cmdVirtualKey: Int? = nil, cmdGlyph: Int? = nil, children: [AXMenuNode] = []) {
        self.role = role
        self.title = title
        self.isEnabled = isEnabled
        self.cmdChar = cmdChar
        self.cmdModifiers = cmdModifiers
        self.cmdVirtualKey = cmdVirtualKey
        self.cmdGlyph = cmdGlyph
        self.children = children
    }
}

public struct MenuSnapshot: Codable, Sendable, Equatable {
    public var bundleID: String
    public var appName: String
    public var barItems: [AXMenuNode]
    public var isPartial: Bool
    /// Leading `barItems` read in full. The walk stops at the first failed read or at its budget,
    /// so only a bar item at or past this index can be cut short.
    public var completeBarItemCount: Int
    public var takenAt: Date

    public init(bundleID: String, appName: String, barItems: [AXMenuNode], isPartial: Bool, completeBarItemCount: Int, takenAt: Date) {
        self.bundleID = bundleID
        self.appName = appName
        self.barItems = barItems
        self.isPartial = isPartial
        self.completeBarItemCount = completeBarItemCount
        self.takenAt = takenAt
    }
}
