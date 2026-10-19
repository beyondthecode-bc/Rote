import AppKit
import RoteCore
import SwiftUI

struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: DesignTokens.sectionLabelSize, weight: .semibold, design: .rounded))
            .tracking(DesignTokens.sectionLabelTracking)
            .foregroundStyle(.tertiary)
    }
}

struct AppHeaderRow: View {
    let bundleID: String

    var body: some View {
        let info = AppInfo.resolve(bundleID)
        HStack(spacing: 6) {
            Image(nsImage: info.icon).resizable().frame(width: 16, height: 16)
            Text(info.name)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }
}

struct CoachingRow: View {
    let record: ItemRecord
    let onSnooze: () -> Void

    @State private var hovering = false
    @FocusState private var snoozeFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(record.item.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(l("popover.uses", "\(record.menuUses.count)"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(DesignTokens.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(DesignTokens.accent.opacity(0.18), in: Capsule())
            Spacer(minLength: 8)
            KeycapGroupView(shortcut: record.item.shortcut, size: .popover)
            Button(l("nudge.snooze"), action: onSnooze)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.system(size: 10))
                .focused($snoozeFocused)
                .opacity(hovering || snoozeFocused ? 1 : 0)
        }
        .padding(.vertical, 3)
        .padding(.leading, 22)
        .padding(.trailing, 4)
        .background(hovering ? Color.primary.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.spokenLabel)
        .accessibilityValue(l("popover.uses", "\(record.menuUses.count)"))
        .accessibilityAction(named: l("nudge.snooze"), onSnooze)
    }
}

struct LearnedRow: View {
    let record: ItemRecord

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DesignTokens.learned)
            Text(record.item.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            KeycapGroupView(shortcut: record.item.shortcut, size: .popover)
                .opacity(0.6)
        }
        .padding(.vertical, 3)
        .padding(.leading, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(record.spokenLabel)
    }
}

private extension ItemRecord {
    /// "Reload Page, Command R", the sentence the HUD and the overlay speak (spec §8).
    var spokenLabel: String {
        item.title + (item.shortcut.map { ", " + GlyphFormatter.spokenDescription($0) } ?? "")
    }
}
