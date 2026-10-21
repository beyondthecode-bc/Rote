import AppKit
import RoteCore
import SwiftUI

/// Every shortcut of the frontmost app, one column per menu (spec §7.2).
struct ShortcutSheetView: View {
    let tree: MenuTree
    let appIcon: NSImage
    let coaching: Set<String>
    let learned: Set<String>
    let showAppleMenu: Bool
    let showItemsWithoutShortcuts: Bool
    let dismissHint: String
    /// Changes on every show, so the reused sheet opens scrolled to the top.
    let presentation: Int

    @State private var viewportHeight: CGFloat = 0
    @State private var contentHeight: CGFloat = 0

    private static let top = "top"

    private var visibleMenus: [MenuTree.Menu] {
        tree.menus
            .filter { showAppleMenu || !$0.isAppleMenu }
            .filter { menu in menu.items.contains { showItemsWithoutShortcuts || $0.shortcut != nil || $0.hasUnrenderableShortcut } }
    }

    /// The rows drawn with keycaps, "?" ones included.
    private var shortcutCount: Int {
        visibleMenus.flatMap(\.items).filter { $0.shortcut != nil || $0.hasUnrenderableShortcut }.count
    }

    private var isScrollable: Bool { viewportHeight > 0 && contentHeight > viewportHeight + 1 }

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Color.black.opacity(0.55)
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        FlowLayout(spacing: DesignTokens.overlayColumnSpacing) {
                            ForEach(Array(visibleMenus.enumerated()), id: \.offset) { _, menu in
                                MenuColumnView(menu: menu, coaching: coaching, learned: learned, showItemsWithoutShortcuts: showItemsWithoutShortcuts)
                                    .frame(width: DesignTokens.overlayColumnWidth, alignment: .topLeading)
                            }
                        }
                        .padding(32)
                        .id(Self.top)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                    }
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
                    .onChange(of: presentation) { proxy.scrollTo(Self.top, anchor: .top) }
                }
                footer
            }
        }
        .ignoresSafeArea()
        .environment(\.colorScheme, .dark)
        .accessibilityElement(children: .contain)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(nsImage: appIcon).resizable().frame(width: 18, height: 18)
            Text(tree.appName).fontWeight(.semibold).lineLimit(1).truncationMode(.middle)
            Text("·").foregroundStyle(.tertiary)
            Text(l("overlay.count", count: shortcutCount, number(shortcutCount)))
            if tree.isPartial {
                Text("·").foregroundStyle(.tertiary)
                Text(l("overlay.partial")).foregroundStyle(DesignTokens.accent)
            }
            if isScrollable {
                Text("·").foregroundStyle(.tertiary)
                Text(l("overlay.scrollHint"))
            }
            Spacer()
            Text(dismissHint)
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(.black.opacity(0.25))
    }
}

struct MenuColumnView: View {
    let menu: MenuTree.Menu
    let coaching: Set<String>
    let learned: Set<String>
    let showItemsWithoutShortcuts: Bool

    private var rows: [MenuItemRecord] {
        menu.items.filter { showItemsWithoutShortcuts || $0.shortcut != nil || $0.hasUnrenderableShortcut }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(menu.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.66)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.bottom, 6)
            // Keyed by position: two windows named "Untitled" share an identity.
            ForEach(Array(rows.enumerated()), id: \.offset) { _, item in
                row(item)
            }
        }
    }

    private func row(_ item: MenuItemRecord) -> some View {
        let isCoaching = coaching.contains(item.identity)
        let hasShortcut = item.shortcut != nil || item.hasUnrenderableShortcut
        return HStack(spacing: 8) {
            if isCoaching {
                Circle().fill(DesignTokens.accent).frame(width: 6, height: 6)
            }
            VStack(alignment: .leading, spacing: 0) {
                if !item.parentPath.isEmpty {
                    Text(item.parentPath.joined(separator: " › ") + " ›")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(item.title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            if learned.contains(item.identity) {
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DesignTokens.learned)
            }
            if hasShortcut {
                KeycapGroupView(shortcut: item.shortcut, size: .overlay)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(isCoaching ? DesignTokens.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        .opacity(!hasShortcut ? 0.45 : (item.isEnabled ? 1 : 0.6))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenMenuItem(item.title, shortcut: item.shortcut))
    }
}
