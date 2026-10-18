import Foundation

/// The single source of truth for how a shortcut is drawn and spoken.
public enum GlyphFormatter {
    public static let unrenderableSymbol = "?"

    public static func modifierSegments(_ modifiers: Modifiers) -> [String] {
        var out: [String] = []
        if modifiers.contains(.control) { out.append("⌃") }
        if modifiers.contains(.option) { out.append("⌥") }
        if modifiers.contains(.shift) { out.append("⇧") }
        if modifiers.contains(.command) { out.append("⌘") }
        return out
    }

    public static func keySymbol(_ key: Key) -> String {
        switch key {
        case .character(let c): return c
        case .special(let s): return specialSymbols[s] ?? s.rawValue.uppercased()
        }
    }

    /// One string per keycap, in display order.
    public static func segments(_ shortcut: Shortcut) -> [String] {
        modifierSegments(shortcut.modifiers) + [keySymbol(shortcut.key)]
    }

    public static func display(_ shortcut: Shortcut) -> String {
        segments(shortcut).joined()
    }

    /// For VoiceOver: "Shift Command N".
    public static func spokenDescription(_ shortcut: Shortcut) -> String {
        var words: [String] = []
        if shortcut.modifiers.contains(.control) { words.append("Control") }
        if shortcut.modifiers.contains(.option) { words.append("Option") }
        if shortcut.modifiers.contains(.shift) { words.append("Shift") }
        if shortcut.modifiers.contains(.command) { words.append("Command") }
        switch shortcut.key {
        case .character(let c): words.append(c)
        case .special(let s): words.append(spokenSpecial[s] ?? s.rawValue.uppercased())
        }
        return words.joined(separator: " ")
    }

    private static let specialSymbols: [SpecialKey: String] = [
        .escape: "⎋", .tab: "⇥", .space: "␣", .delete: "⌫", .forwardDelete: "⌦",
        .returnKey: "↩", .enter: "⌤", .upArrow: "↑", .downArrow: "↓", .leftArrow: "←",
        .rightArrow: "→", .pageUp: "⇞", .pageDown: "⇟", .home: "↖", .end: "↘",
        .help: "?", .clear: "⌧",
    ]

    private static let spokenSpecial: [SpecialKey: String] = [
        .escape: "Escape", .tab: "Tab", .space: "Space", .delete: "Delete",
        .forwardDelete: "Forward Delete", .returnKey: "Return", .enter: "Enter",
        .upArrow: "Up Arrow", .downArrow: "Down Arrow", .leftArrow: "Left Arrow",
        .rightArrow: "Right Arrow", .pageUp: "Page Up", .pageDown: "Page Down",
        .home: "Home", .end: "End", .help: "Help", .clear: "Clear",
    ]
}
