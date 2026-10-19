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
                Text(l("onboarding.demoItem")).font(.system(size: 13, weight: .semibold))
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

    /// Rote's own window is frontmost here, so the step sends the user to another app first. Until
    /// Accessibility is granted no key reaches Rote, so the step says so instead of a prompt that
    /// would do nothing; the check appears once the sheet has been shown.
    private var tryItStep: some View {
        let shown = container.overlay.hasShownOnce
        let granted = container.engine.permissionGranted
        let trigger = container.settings.overlayTrigger
        return VStack(alignment: .leading, spacing: 18) {
            Text(l("onboarding.title3")).font(.system(size: 20, weight: .bold))
            Text(Self.tryItText(trigger: trigger, accessGranted: granted))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if granted || shown {
                HStack(spacing: 12) {
                    triggerKeys(trigger)
                    Image(systemName: shown ? "checkmark.circle.fill" : "arrow.left")
                        .foregroundStyle(shown ? DesignTokens.learned : .secondary)
                    if shown { Text(l("onboarding.tried")).font(.system(size: 12)) }
                }
            }
            if #available(macOS 27, *) { menuBarHint }
        }
    }

    /// The keys of the trigger chosen in Settings › Overlay.
    @ViewBuilder
    private func triggerKeys(_ trigger: AppSettings.OverlayTrigger) -> some View {
        switch trigger {
        case .holdCommand: KeycapView(symbol: "⌘", size: .hud)
        case .holdOption: KeycapView(symbol: "⌥", size: .hud)
        case .stickyHotkey: KeycapGroupView(shortcut: HoldDetector.stickyHotkey, size: .hud)
        }
    }

    /// Step 3's instruction for `trigger`, or, while Accessibility is missing, the note that the demo needs it.
    static func tryItText(trigger: AppSettings.OverlayTrigger, accessGranted: Bool, strings: LocalizationManager = .shared) -> String {
        guard accessGranted else { return strings.string(for: "onboarding.needsAccess") }
        let action: String
        switch trigger {
        case .holdCommand: action = strings.string(for: "onboarding.trigger.command")
        case .holdOption: action = strings.string(for: "onboarding.trigger.option")
        case .stickyHotkey: action = strings.string(for: "onboarding.trigger.sticky")
        }
        return strings.string(for: "onboarding.tryIt", [action])
    }

    /// On macOS 27 a new menu bar app can start among the hidden items. The system's own button, two
    /// left arrows labelled "Show Hidden Menu Bar Items", reveals them: the hint names it as the system does.
    /// Shown on macOS 27 and later only: macOS 14 and 15 have no such button, and macOS 26 is unconfirmed.
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

    /// Closing the window marks onboarding completed (OnboardingWindow), however it closes.
    private func finish() {
        OnboardingWindow.close()
    }
}
