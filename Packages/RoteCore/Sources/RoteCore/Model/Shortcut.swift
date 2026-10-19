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
    /// 8 = no ⌘, 16 = fn (see `ShortcutDecoding.functionMask`). Zero therefore means ⌘ alone.
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

    /// F1–F20: the only keys that count as a shortcut with no modifier held.
    public var isFunctionKey: Bool {
        switch self {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
             .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            return true
        default:
            return false
        }
    }
}

public enum Key: Codable, Hashable, Sendable {
    /// A single printable scalar as drawn on the keycap: uppercased when that stays one
    /// scalar ("R", "[", "1"), otherwise as-is ("ß"). Built through `KeyTables.keycapCharacter`.
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

    /// Whether a press of this shortcut can be told apart from typing: it needs ⌘, ⌃ or ⌥,
    /// or an F-key. Plain ⌫ or ⇧→ in a text field look exactly like editing, so Rote neither
    /// counts such presses nor coaches such items (spec §5.5, §6.2 rule 3).
    public var isObservable: Bool {
        if !modifiers.subtracting(.shift).isEmpty { return true }
        if case .special(let special) = key { return special.isFunctionKey }
        return false
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

    /// `AXMenuItemCmdModifiers` bit for fn/Globe. Rote has no keycap for it and its key monitor
    /// cannot tell fn ⌃F from ⌃F, so such items are unrenderable rather than taught as a key
    /// that does something else (spec §5.4).
    public static let functionMask = 16

    /// Precedence: glyph table, then the scalar table (control and function-key scalars),
    /// then a printable character, then the virtual key code.
    ///
    /// Accessibility reports letter key equivalents in uppercase and Shift only through mask
    /// bit 1, so the character's case never implies Shift ("N" with mask 0 is ⌘N).
    /// - Parameters:
    ///   - cmdChar: `AXMenuItemCmdChar`
    ///   - modifierMask: `AXMenuItemCmdModifiers`
    ///   - virtualKey: `AXMenuItemCmdVirtualKey`
    ///   - glyph: `AXMenuItemCmdGlyph`
    public static func decode(cmdChar: String?, modifierMask: Int?, virtualKey: Int?, glyph: Int?) -> Result {
        let char = (cmdChar ?? "").precomposedStringWithCanonicalMapping
        let glyphCode = glyph ?? 0
        let keyCode = virtualKey ?? 0
        guard !char.isEmpty || glyphCode > 0 || keyCode > 0 else { return .none }

        let mask = modifierMask ?? 0
        if mask & functionMask != 0 { return .unrenderable }
        var modifiers = Modifiers.fromAXMask(mask)

        if glyphCode > 0, let special = KeyTables.special(forGlyph: glyphCode) {
            // kMenuTabLeftGlyph is Shift-Tab even when the mask omits Shift.
            if glyphCode == KeyTables.backTabGlyph { modifiers.insert(.shift) }
            return .shortcut(Shortcut(modifiers: modifiers, key: .special(special)))
        }
        // Accessibility uppercases the key equivalent, and some letters uppercase to several
        // ("ß" arrives as "SS"): the first scalar alone would claim a different key.
        if char.unicodeScalars.count > 1 { return .unrenderable }
        if let scalar = char.unicodeScalars.first {
            if let special = KeyTables.special(forScalar: scalar) {
                // NSBackTabCharacter is Shift-Tab even when the mask omits Shift.
                if scalar.value == KeyTables.backTabScalar { modifiers.insert(.shift) }
                return .shortcut(Shortcut(modifiers: modifiers, key: .special(special)))
            }
            if let legend = KeyTables.keycapCharacter(for: scalar) {
                return .shortcut(Shortcut(modifiers: modifiers, key: .character(legend)))
            }
        }
        if keyCode > 0, let special = KeyTables.special(forKeyCode: keyCode) {
            return .shortcut(Shortcut(modifiers: modifiers, key: .special(special)))
        }
        return .unrenderable
    }
}
