import RoteCore
import SwiftUI

/// One physical-looking key. Three sizes (spec §8).
struct KeycapView: View {
    enum Size {
        case hud, overlay, popover

        var height: CGFloat {
            switch self { case .hud: 36; case .overlay: 20; case .popover: 18 }
        }
        var fontSize: CGFloat {
            switch self { case .hud: 18; case .overlay: 11; case .popover: 10 }
        }
        var radius: CGFloat {
            switch self { case .hud: 8; case .overlay, .popover: 5 }
        }
        var horizontalPadding: CGFloat {
            switch self { case .hud: 12; case .overlay, .popover: 6 }
        }
        var spacing: CGFloat {
            switch self { case .hud: 6; case .overlay, .popover: 3 }
        }
    }

    let symbol: String
    let size: Size

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text(symbol)
            .font(.system(size: size.fontSize, weight: .semibold, design: .rounded))
            .foregroundStyle(textColor)
            .lineLimit(1)
            .fixedSize()
            .frame(minWidth: size.height, minHeight: size.height)
            .padding(.horizontal, size.horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                    .fill(LinearGradient(colors: faceColors, startPoint: .top, endPoint: .bottom))
                    .overlay(
                        RoundedRectangle(cornerRadius: size.radius, style: .continuous)
                            .strokeBorder(edgeColor, lineWidth: contrast == .increased ? 1.5 : 0.75)
                    )
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.5 : 0.18), radius: size == .hud ? 3 : 1, y: size == .hud ? 2 : 1)
            )
            .accessibilityHidden(true)
    }

    private var faceColors: [Color] {
        colorScheme == .dark ? [Color(white: 0.26), Color(white: 0.17)] : [.white, Color(white: 0.90)]
    }

    private var textColor: Color {
        colorScheme == .dark ? .white : Color(white: 0.08)
    }

    private var edgeColor: Color {
        colorScheme == .dark ? Color(white: 0.04) : Color(white: 0.72)
    }
}

/// A whole shortcut as a row of keycaps, or a single "?" when it cannot be rendered.
struct KeycapGroupView: View {
    let shortcut: Shortcut?
    let size: KeycapView.Size

    var body: some View {
        HStack(spacing: size.spacing) {
            if let shortcut {
                ForEach(Array(GlyphFormatter.segments(shortcut).enumerated()), id: \.offset) { _, symbol in
                    KeycapView(symbol: symbol, size: size)
                }
            } else {
                KeycapView(symbol: GlyphFormatter.unrenderableSymbol, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shortcut.map { spokenShortcut($0) } ?? l("keycap.unknown"))
    }
}

/// What VoiceOver reads for a shortcut, in Rote's language: "Shift Command N", "Maj Commande N".
/// Modifiers and named keys come from the `spoken.*` strings; F-keys and character keys are read
/// as drawn. A table without those names reads RoteCore's English description instead.
@MainActor
func spokenShortcut(_ shortcut: Shortcut, localization: LocalizationManager = .shared) -> String {
    var keys: [String] = []
    if shortcut.modifiers.contains(.control) { keys.append("spoken.control") }
    if shortcut.modifiers.contains(.option) { keys.append("spoken.option") }
    if shortcut.modifiers.contains(.shift) { keys.append("spoken.shift") }
    if shortcut.modifiers.contains(.command) { keys.append("spoken.command") }
    var drawnKey: String?
    switch shortcut.key {
    case .character(let character): drawnKey = character
    case .special(let special) where special.isFunctionKey: drawnKey = GlyphFormatter.spokenName(for: special)
    case .special(let special): keys.append("spoken.key.\(special.rawValue)")
    }

    var words: [String] = []
    for key in keys {
        let word = localization.string(for: key)
        guard word != key else { return GlyphFormatter.spokenDescription(shortcut) }
        words.append(word)
    }
    if let drawnKey { words.append(drawnKey) }
    return words.joined(separator: " ")
}

/// "Reload Page, Command R": a menu item as the HUD, the overlay and the popover speak it (spec §8).
@MainActor
func spokenMenuItem(_ title: String, shortcut: Shortcut?, localization: LocalizationManager = .shared) -> String {
    guard let shortcut else { return title }
    return title + ", " + spokenShortcut(shortcut, localization: localization)
}

#Preview("Keycaps") {
    VStack(spacing: 16) {
        KeycapGroupView(shortcut: Shortcut(modifiers: [.option, .shift, .command], key: .character("V")), size: .hud)
        KeycapGroupView(shortcut: Shortcut(modifiers: [.command], key: .special(.delete)), size: .overlay)
        KeycapGroupView(shortcut: nil, size: .popover)
    }
    .padding(30)
}
