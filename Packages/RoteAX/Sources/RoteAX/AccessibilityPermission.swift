import AppKit
import ApplicationServices

public enum AccessibilityPermission {
    public static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt once and returns the current trust state.
    @discardableResult
    public static func requestWithPrompt() -> Bool {
        AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    @MainActor
    public static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
