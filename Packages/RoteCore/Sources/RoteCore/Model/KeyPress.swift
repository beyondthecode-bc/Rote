import Foundation

/// One key press as the key monitor reports it, and the rule that matches it to menu items
/// (spec §5.5). Character keys go through `KeyTables.keycapCharacter`, the rule the AX decoder
/// uses, so both sides agree.
public struct KeyPress: Sendable, Equatable {
    /// `charactersIgnoringModifiers`: the key through the current layout with only ⇧ applied.
    public var characters: String
    /// The key through the layout's ⌘ table (`characters(byApplyingModifiers: .command)`);
    /// empty when ⌘ is not held. Non-Latin layouts (Russian, Greek) and Dvorak - QWERTY ⌘
    /// switch to a Latin table while ⌘ is down, and AppKit fires key equivalents through it.
    public var commandCharacters: String
    public var keyCode: UInt16
    /// Masked to ⌃⌥⇧⌘.
    public var modifiers: Modifiers

    public init(characters: String, commandCharacters: String, keyCode: UInt16, modifiers: Modifiers) {
        self.characters = characters
        self.commandCharacters = commandCharacters
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The shortcuts this press can fire, most specific first. Modifier-less presses only count
    /// for F-keys, so ordinary typing never matches an item. With ⌘ held the ⌘ table comes first
    /// and is final for letters: on Dvorak - QWERTY ⌘ the key that types "o" fires ⌘S, never ⌘O.
    /// A symbol typed with ⇧ is then tried as typed, and again without ⇧, because AppKit reports
    /// items such as Help "⌘?" and Zoom In "⌘+" without the ⇧ that typing them needs.
    public var candidateShortcuts: [Shortcut] {
        if let special = KeyTables.special(forKeyCode: Int(keyCode)) {
            guard !modifiers.isEmpty || special.isFunctionKey else { return [] }
            return [Shortcut(modifiers: modifiers, key: .special(special))]
        }
        guard !modifiers.isEmpty else { return [] }
        var result: [Shortcut] = []
        func add(_ scalar: Unicode.Scalar?, _ modifiers: Modifiers) {
            guard let scalar, let legend = KeyTables.keycapCharacter(for: scalar) else { return }
            let shortcut = Shortcut(modifiers: modifiers, key: .character(legend))
            if !result.contains(shortcut) { result.append(shortcut) }
        }
        let commandScalar = modifiers.contains(.command) ? Self.firstScalar(commandCharacters) : nil
        add(commandScalar, modifiers)
        guard let typed = Self.firstScalar(characters) else { return result }
        if commandScalar != nil && typed.properties.isAlphabetic { return result }
        add(typed, modifiers)
        let uncased = String(typed).uppercased() == String(typed).lowercased()
        if modifiers.contains(.shift) && uncased { add(typed, modifiers.subtracting(.shift)) }
        return result
    }

    private static func firstScalar(_ text: String) -> Unicode.Scalar? {
        text.precomposedStringWithCanonicalMapping.unicodeScalars.first
    }
}

extension MenuTree {
    /// The item a key press fires: the first candidate shortcut bound to an enabled item.
    public func item(for press: KeyPress) -> MenuItemRecord? {
        for shortcut in press.candidateShortcuts {
            if let match = item(for: shortcut) { return match }
        }
        return nil
    }
}
