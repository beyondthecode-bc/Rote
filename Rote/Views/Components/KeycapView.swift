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
        .accessibilityLabel(shortcut.map(GlyphFormatter.spokenDescription) ?? "Unknown shortcut")
    }
}

#Preview("Keycaps") {
    VStack(spacing: 16) {
        KeycapGroupView(shortcut: Shortcut(modifiers: [.option, .shift, .command], key: .character("V")), size: .hud)
        KeycapGroupView(shortcut: Shortcut(modifiers: [.command], key: .special(.delete)), size: .overlay)
        KeycapGroupView(shortcut: nil, size: .popover)
    }
    .padding(30)
}
