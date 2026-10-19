import AppKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?
    /// The window's delegate, which the window holds only weakly.
    private static var closeObserver: CloseObserver?

    static func show(container: AppContainer, step: Int = 0) {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let host = NSHostingController(rootView: OnboardingView(initialStep: step).environment(container))
        let newWindow = NSWindow(contentViewController: host)
        newWindow.title = l("app.name")
        newWindow.styleMask = [.titled, .closable]
        newWindow.isReleasedWhenClosed = false
        newWindow.setContentSize(NSSize(width: DesignTokens.onboardingSize.width, height: DesignTokens.onboardingSize.height))
        let observer = CloseObserver(settings: container.settings)
        newWindow.delegate = observer
        closeObserver = observer
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    static func close() {
        window?.close()
    }

    /// Done, the close button and ⌘W all end the first run: onboarding never comes back on its own
    /// (spec §7.5). Access still missing shows on the menu bar icon, and the popover offers the permission step.
    private final class CloseObserver: NSObject, NSWindowDelegate {
        private let settings: AppSettings

        init(settings: AppSettings) {
            self.settings = settings
        }

        func windowWillClose(_ notification: Notification) {
            settings.hasCompletedOnboarding = true
            OnboardingWindow.window = nil
        }
    }
}
