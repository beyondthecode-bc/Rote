import AppKit
import RoteCore
import SwiftUI

struct NudgeModel {
    let record: ItemRecord
    let appName: String
    let appIcon: NSImage?
    /// Screen location of the pointer when the nudge appeared. A card that appears under a
    /// resting pointer counts as hovered only once the pointer moves.
    let pointerAtShow: NSPoint
}

/// The lesson: keycaps, item title, "Safari · 3 menu uses this week", hover-revealed snooze.
struct NudgeView: View {
    let model: NudgeModel
    let controller: NudgeController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 10) {
            KeycapGroupView(shortcut: model.record.item.shortcut, size: .hud)
            Text(model.record.item.title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                if let icon = model.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                Text(l("nudge.subtitle", count: model.record.menuUses.count, model.appName, number(model.record.menuUses.count)))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            snoozeMenu
                .opacity(hovering ? 1 : 0)
                .frame(height: hovering ? nil : 0)
                .clipped()
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
        .frame(minWidth: 240, maxWidth: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.hudCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.hudCornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08))
        )
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.96)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(duration: 0.18)) { appeared = true }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active:
                guard !hovering, NSEvent.mouseLocation != model.pointerAtShow else { return }
                setHovering(true)
            case .ended:
                guard hovering else { return }
                setHovering(false)
            }
        }
        .padding(DesignTokens.hudShadowPadding)
    }

    private func setHovering(_ isHovering: Bool) {
        withAnimation(.easeOut(duration: 0.12)) { hovering = isHovering }
        controller.setHovering(isHovering)
    }

    private var snoozeMenu: some View {
        Menu {
            Button(l("nudge.snoozeWeek")) { controller.snoozeCurrent() }
            Button(l("nudge.stopItem")) { controller.muteCurrent() }
            Divider()
            Button(l("nudge.pauseHour")) { controller.pauseForAnHour() }
        } label: {
            Label(l("nudge.snooze"), systemImage: "chevron.down")
                .font(.system(size: 11))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
