import RoteAX
import SwiftUI

/// Minimal status view used until Task 16 replaces it with the progress popover.
struct StatusPopoverView: View {
    @Environment(AppContainer.self) private var container

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if container.engine.permissionGranted {
                Text("Rote is watching your menus.")
                Text("\(container.engine.currentApp?.name ?? "—") · \(container.engine.currentTree?.shortcutCount ?? 0) shortcuts")
                    .foregroundStyle(.secondary)
            } else {
                Text(l("permission.title")).font(.headline)
                Button(l("permission.open")) {
                    AccessibilityPermission.requestWithPrompt()
                    AccessibilityPermission.openSystemSettings()
                }
            }
            #if DEBUG
            Divider()
            Button("Simulate nudge") { container.simulateNudge() }
            Button("Export menu snapshot") { container.exportSnapshot() }
            #endif
            Divider()
            Button(l("app.quit")) { NSApp.terminate(nil) }
        }
        .padding(14)
        .frame(width: 300)
    }
}
