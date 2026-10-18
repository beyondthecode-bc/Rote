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
        case .special(let s): return symbol(for: s)
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
        case .special(let s): words.append(spokenName(for: s))
        }
        return words.joined(separator: " ")
    }

    /// Exhaustive on purpose: adding a `SpecialKey` without a symbol fails to compile.
    public static func symbol(for key: SpecialKey) -> String {
        switch key {
        case .escape: return "⎋"
        case .tab: return "⇥"
        case .space: return "␣"
        case .delete: return "⌫"
        case .forwardDelete: return "⌦"
        case .returnKey: return "↩"
        case .enter: return "⌤"
        case .upArrow: return "↑"
        case .downArrow: return "↓"
        case .leftArrow: return "←"
        case .rightArrow: return "→"
        case .pageUp: return "⇞"
        case .pageDown: return "⇟"
        case .home: return "↖"
        case .end: return "↘"
        case .help: return "Help"
        case .clear: return "⌧"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
             .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            return key.rawValue.uppercased()
        }
    }

    public static func spokenName(for key: SpecialKey) -> String {
        switch key {
        case .escape: return "Escape"
        case .tab: return "Tab"
        case .space: return "Space"
        case .delete: return "Delete"
        case .forwardDelete: return "Forward Delete"
        case .returnKey: return "Return"
        case .enter: return "Enter"
        case .upArrow: return "Up Arrow"
        case .downArrow: return "Down Arrow"
        case .leftArrow: return "Left Arrow"
        case .rightArrow: return "Right Arrow"
        case .pageUp: return "Page Up"
        case .pageDown: return "Page Down"
        case .home: return "Home"
        case .end: return "End"
        case .help: return "Help"
        case .clear: return "Clear"
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
             .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            return key.rawValue.uppercased()
        }
    }
}
