import Foundation

/// Modifier keys. Display order is always ⌃ ⌥ ⇧ ⌘ (see GlyphFormatter).
public struct Modifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let control = Modifiers(rawValue: 1 << 0)
    public static let option = Modifiers(rawValue: 1 << 1)
    public static let shift = Modifiers(rawValue: 1 << 2)
    public static let command = Modifiers(rawValue: 1 << 3)

    /// Decodes `AXMenuItemCmdModifiers`. Values combine: 1 = ⇧, 2 = ⌥, 4 = ⌃,
    /// 8 = no ⌘. Zero therefore means ⌘ alone.
    public static func fromAXMask(_ mask: Int) -> Modifiers {
        var result: Modifiers = []
        if mask & 1 != 0 { result.insert(.shift) }
        if mask & 2 != 0 { result.insert(.option) }
        if mask & 4 != 0 { result.insert(.control) }
        if mask & 8 == 0 { result.insert(.command) }
        return result
    }
}

public enum SpecialKey: String, Codable, Hashable, Sendable, CaseIterable {
    case escape, tab, space, delete, forwardDelete, returnKey, enter
    case upArrow, downArrow, leftArrow, rightArrow
    case pageUp, pageDown, home, end, help, clear
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case f11, f12, f13, f14, f15, f16, f17, f18, f19, f20
}

public enum Key: Codable, Hashable, Sendable {
    /// A single printable character, stored uppercased ("R", "[", "1").
    case character(String)
    case special(SpecialKey)
}

public struct Shortcut: Codable, Hashable, Sendable {
    public var modifiers: Modifiers
    public var key: Key

    public init(modifiers: Modifiers, key: Key) {
        self.modifiers = modifiers
        self.key = key
    }
}

/// Turns raw Accessibility menu-item attributes into a `Shortcut`.
public enum ShortcutDecoding {
    public enum Result: Equatable, Sendable {
        /// The item has no key equivalent at all.
        case none
        case shortcut(Shortcut)
        /// The item claims a key equivalent Rote cannot render. Shown as "?", never coached.
        case unrenderable
    }

    /// - Parameters:
    ///   - cmdChar: `AXMenuItemCmdChar`
    ///   - modifierMask: `AXMenuItemCmdModifiers`
    ///   - virtualKey: `AXMenuItemCmdVirtualKey`
    ///   - glyph: `AXMenuItemCmdGlyph`
    public static func decode(cmdChar: String?, modifierMask: Int?, virtualKey: Int?, glyph: Int?) -> Result {
        let char = cmdChar ?? ""
        let glyphCode = glyph ?? 0
        let keyCode = virtualKey ?? 0
        guard !char.isEmpty || glyphCode > 0 || keyCode > 0 else { return .none }

        var modifiers = Modifiers.fromAXMask(modifierMask ?? 0)

        if glyphCode > 0, let special = KeyTables.special(forGlyph: glyphCode) {
            return .shortcut(Shortcut(modifiers: modifiers, key: .special(special)))
        }
        if let scalar = char.unicodeScalars.first {
            if let special = KeyTables.special(forScalar: scalar) {
                return .shortcut(Shortcut(modifiers: modifiers, key: .special(special)))
            }
            if KeyTables.isPrintable(scalar) {
                // AppKit treats an uppercase key equivalent as "needs Shift" even when
                // the modifier mask does not say so; the menu bar draws ⇧ for it.
                if scalar.properties.isUppercase { modifiers.insert(.shift) }
                return .shortcut(Shortcut(modifiers: modifiers, key: .character(String(scalar).uppercased())))
            }
        }
        if keyCode > 0, let special = KeyTables.special(forKeyCode: keyCode) {
            return .shortcut(Shortcut(modifiers: modifiers, key: .special(special)))
        }
        return .unrenderable
    }
}
