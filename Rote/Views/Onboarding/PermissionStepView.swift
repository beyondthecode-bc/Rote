import RoteAX
import SwiftUI

/// Shared by onboarding step 2 and the popover when access is missing.
struct PermissionStepView: View {
    let granted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(l("permission.title"))
                .font(.system(size: 14, weight: .semibold))
            Text(l("permission.body"))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Image(systemName: granted ? "checkmark.circle.fill" : "clock")
                    .foregroundStyle(granted ? DesignTokens.learned : .secondary)
                Text(granted ? l("permission.granted") : l(PermissionPane.key("permission.waiting")))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !granted {
                Button(l("permission.open")) {
                    AccessibilityPermission.requestWithPrompt()
                    AccessibilityPermission.openSystemSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accent)
            }
        }
    }
}
