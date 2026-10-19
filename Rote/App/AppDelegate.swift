import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting unit tests: no engine, no update check, nothing written to the user's state.
        guard !Self.isTestHost() else { return }
        AppContainer.shared.start()
    }

    /// Flush pending state before the process goes away.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !Self.isTestHost() else { return .terminateNow }
        Task { @MainActor in
            await AppContainer.shared.engine.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// True when XCTest launched this process to host a test bundle.
    nonisolated static func isTestHost(environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment["XCTestConfigurationFilePath"] != nil
    }
}
