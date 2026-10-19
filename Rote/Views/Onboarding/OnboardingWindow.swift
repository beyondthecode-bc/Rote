import AppKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?

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
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = newWindow
    }

    static func close() {
        window?.close()
    }
}
