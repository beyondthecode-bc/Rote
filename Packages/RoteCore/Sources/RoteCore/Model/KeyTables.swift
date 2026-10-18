import Foundation

/// Lookup tables shared by decoding (AX attributes) and matching (NSEvent key codes).
public enum KeyTables {
    /// Carbon `kMenu*Glyph` values exposed through `AXMenuItemCmdGlyph`.
    private static let glyphTable: [Int: SpecialKey] = [
        2: .tab, 4: .enter, 9: .space, 10: .forwardDelete, 11: .returnKey,
        23: .delete, 27: .escape, 28: .clear,
        98: .pageUp, 100: .leftArrow, 101: .rightArrow, 102: .home, 103: .help,
        104: .upArrow, 105: .end, 106: .downArrow, 107: .pageDown,
        111: .f1, 112: .f2, 113: .f3, 114: .f4, 115: .f5, 116: .f6, 117: .f7, 118: .f8,
        119: .f9, 120: .f10, 121: .f11, 122: .f12, 135: .f13, 136: .f14, 137: .f15,
        143: .f16, 144: .f17, 145: .f18, 146: .f19,
    ]

    /// Control characters and AppKit function-key scalars used as key equivalents.
    private static let scalarTable: [UInt32: SpecialKey] = [
        0x08: .delete, 0x7F: .delete, 0x09: .tab, 0x19: .tab,
        0x0D: .returnKey, 0x0A: .returnKey, 0x03: .enter, 0x1B: .escape, 0x20: .space,
        0xF700: .upArrow, 0xF701: .downArrow, 0xF702: .leftArrow, 0xF703: .rightArrow,
        0xF704: .f1, 0xF705: .f2, 0xF706: .f3, 0xF707: .f4, 0xF708: .f5, 0xF709: .f6,
        0xF70A: .f7, 0xF70B: .f8, 0xF70C: .f9, 0xF70D: .f10, 0xF70E: .f11, 0xF70F: .f12,
        0xF710: .f13, 0xF711: .f14, 0xF712: .f15, 0xF713: .f16, 0xF714: .f17, 0xF715: .f18,
        0xF716: .f19, 0xF717: .f20,
        0xF728: .forwardDelete, 0xF729: .home, 0xF72B: .end, 0xF72C: .pageUp, 0xF72D: .pageDown,
        0xF739: .clear, 0xF746: .help,
    ]

    /// Carbon `kVK_*` virtual key codes, as delivered by `NSEvent.keyCode`.
    private static let keyCodeTable: [Int: SpecialKey] = [
        36: .returnKey, 48: .tab, 49: .space, 51: .delete, 53: .escape, 71: .clear, 76: .enter,
        114: .help, 115: .home, 116: .pageUp, 117: .forwardDelete, 119: .end, 121: .pageDown,
        123: .leftArrow, 124: .rightArrow, 125: .downArrow, 126: .upArrow,
        122: .f1, 120: .f2, 99: .f3, 118: .f4, 96: .f5, 97: .f6, 98: .f7, 100: .f8,
        101: .f9, 109: .f10, 103: .f11, 111: .f12, 105: .f13, 107: .f14, 113: .f15,
        106: .f16, 64: .f17, 79: .f18, 80: .f19, 90: .f20,
    ]

    public static func special(forGlyph glyph: Int) -> SpecialKey? { glyphTable[glyph] }
    public static func special(forScalar scalar: Unicode.Scalar) -> SpecialKey? { scalarTable[scalar.value] }
    public static func special(forKeyCode keyCode: Int) -> SpecialKey? { keyCodeTable[keyCode] }

    /// True for characters that can be drawn on a keycap as themselves.
    public static func isPrintable(_ scalar: Unicode.Scalar) -> Bool {
        scalar.value > 0x20 && scalar.value != 0x7F && !(0xF700...0xF8FF).contains(scalar.value)
    }
}
