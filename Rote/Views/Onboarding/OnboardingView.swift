import RoteCore
import SwiftUI

/// Three steps (spec §7.5): the promise, the permission, try it.
struct OnboardingView: View {
    @Environment(AppContainer.self) private var container
    @State private var step: Int

    init(initialStep: Int = 0) {
        _step = State(initialValue: initialStep)
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: promiseStep
                case 1: PermissionStepView(granted: container.engine.permissionGranted)
                default: tryItStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            HStack {
                dots
                Spacer()
                if step < 2 {
                    Button(l("general.next")) { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(l("general.done")) { finish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(28)
        .frame(width: DesignTokens.onboardingSize.width, height: DesignTokens.onboardingSize.height)
    }

    private var promiseStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                KeycapGroupView(shortcut: Shortcut(modifiers: [.command], key: .character("R")), size: .hud)
                Text("Reload Page").font(.system(size: 13, weight: .semibold))
                Text(l("nudge.subtitle", "Safari", "3")).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.hudCornerRadius, style: .continuous))
            Text(l("onboarding.title1")).font(.system(size: 20, weight: .bold))
            Text(l("onboarding.body1")).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tryItStep: some View {
        let shown = container.overlay.hasShownOnce
        return VStack(alignment: .leading, spacing: 18) {
            Text(l("onboarding.title3")).font(.system(size: 20, weight: .bold))
            Text(l("onboarding.body3")).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                KeycapView(symbol: "⌘", size: .hud)
                Image(systemName: shown ? "checkmark.circle.fill" : "arrow.left")
                    .foregroundStyle(shown ? DesignTokens.learned : .secondary)
                if shown { Text(l("onboarding.tried")).font(.system(size: 12)) }
            }
            menuBarHint
        }
    }

    /// On macOS 27 a new menu bar app can start among the hidden items. The system's own button, two
    /// left arrows labelled "Show Hidden Menu Bar Items", reveals them: the hint names it as the system does.
    private var menuBarHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chevron.left.2")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 20)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(DesignTokens.hairline))
                .accessibilityHidden(true)
            Text(l("onboarding.menubarHint"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(index == step ? DesignTokens.accent : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func finish() {
        container.settings.hasCompletedOnboarding = true
        OnboardingWindow.close()
    }
}
