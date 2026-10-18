import Foundation

/// Stable identity for a menu item across launches and dynamic titles.
public enum MenuItemIdentity {
    /// Opening quote → accepted closing quotes, covering the conventions Apple's
    /// localizations use for dynamic names: English and Japanese “…”, straight "…",
    /// single ‘…’, German „…“, Polish, Hungarian and Romanian „…”, German »…«, French «…»,
    /// Swedish ”…”, CJK 「…」 and 『…』. Straight apostrophes are never quotes
    /// ("Don't Save", "Can't Undo Today's Edit").
    private static let closers: [Character: [Character]] = [
        "\"": ["\""], "“": ["”"], "‘": ["’"], "„": ["“", "”"], "»": ["«"], "«": ["»"],
        "”": ["”"], "「": ["」"], "『": ["』"],
    ]

    /// Strips quoted substrings, collapses whitespace runs to one space, trims.
    /// "Close Tab “Example”" and "Close Tab" normalize to the same string.
    /// Single pass, no regex: this runs for every item of every scanned menu.
    public static func normalize(_ title: String) -> String {
        var out = ""
        out.reserveCapacity(title.utf8.count)
        var pendingSpace = false
        var index = title.startIndex
        while index < title.endIndex {
            let character = title[index]
            if let closers = closers[character], let close = closingIndex(for: closers, in: title, after: index) {
                index = title.index(after: close)
                continue
            }
            if character.isWhitespace {
                pendingSpace = true
            } else {
                if pendingSpace && !out.isEmpty { out.append(" ") }
                pendingSpace = false
                out.append(character)
            }
            index = title.index(after: index)
        }
        return out
    }

    /// The first accepted closing quote after `opener`, or nil when the quote is unbalanced.
    /// A ’ followed by a letter is an apostrophe (‘Today’s Notes’), not the close of a ‘…’ quote.
    private static func closingIndex(for closers: [Character], in title: String, after opener: String.Index) -> String.Index? {
        var index = title.index(after: opener)
        while index < title.endIndex {
            let candidate = title[index]
            if closers.contains(candidate) {
                if candidate != "’" { return index }
                let next = title.index(after: index)
                if next == title.endIndex || !title[next].isLetter { return index }
            }
            index = title.index(after: index)
        }
        return nil
    }

    /// A path component that is nothing but a quoted name (a recent document) keeps
    /// its raw title, so two such items never share an identity.
    public static func make(bundleID: String, path: [String]) -> String {
        let parts = path.map { component -> String in
            let normalized = normalize(component)
            return normalized.isEmpty ? component.trimmingCharacters(in: .whitespacesAndNewlines) : normalized
        }
        return bundleID + "|" + parts.joined(separator: "›")
    }
}

/// One menu item of one app: where it lives, what it is called, and its shortcut.
public struct MenuItemRecord: Codable, Hashable, Sendable, Identifiable {
    public let bundleID: String
    /// Menu titles from the menu bar down to the item: ["Edit", "Find", "Find Next"].
    public let path: [String]
    public var shortcut: Shortcut?
    /// The item reports a key equivalent Rote cannot draw. Shown as "?", never coached.
    public var hasUnrenderableShortcut: Bool
    public var isEnabled: Bool
    /// Computed once at creation and never written by this type; the coach re-keys its
    /// records on load, so a change to the rule applies to old state as well.
    public let identity: String

    public init(bundleID: String, path: [String], shortcut: Shortcut?, hasUnrenderableShortcut: Bool = false, isEnabled: Bool = true) {
        self.bundleID = bundleID
        self.path = path
        self.shortcut = shortcut
        self.hasUnrenderableShortcut = hasUnrenderableShortcut
        self.isEnabled = isEnabled
        self.identity = MenuItemIdentity.make(bundleID: bundleID, path: path)
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID, path, shortcut, hasUnrenderableShortcut, isEnabled
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            bundleID: try container.decode(String.self, forKey: .bundleID),
            path: try container.decode([String].self, forKey: .path),
            shortcut: try container.decodeIfPresent(Shortcut.self, forKey: .shortcut),
            hasUnrenderableShortcut: try container.decodeIfPresent(Bool.self, forKey: .hasUnrenderableShortcut) ?? false,
            isEnabled: try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(bundleID, forKey: .bundleID)
        try container.encode(path, forKey: .path)
        try container.encodeIfPresent(shortcut, forKey: .shortcut)
        try container.encode(hasUnrenderableShortcut, forKey: .hasUnrenderableShortcut)
        try container.encode(isEnabled, forKey: .isEnabled)
    }

    public var title: String { path.last ?? "" }
    public var menuTitle: String { path.first ?? "" }
    /// Submenu titles between the top-level menu and the item.
    public var parentPath: [String] { path.count > 2 ? Array(path[1..<(path.count - 1)]) : [] }
    public var id: String { identity }
    public var isCoachable: Bool { shortcut != nil && isEnabled }
}
