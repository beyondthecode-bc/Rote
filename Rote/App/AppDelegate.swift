import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppContainer.shared.start()
    }

    /// Flush pending state before the process goes away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task { @MainActor in
            await AppContainer.shared.engine.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
