import AppKit

/// Reports the frontmost app on start and on every activation.
@MainActor
public final class FrontmostAppTracker {
    public var onActivate: ((AppIdentity) -> Void)?
    private var token: (any NSObjectProtocol)?

    public init() {}

    public func start() {
        guard token == nil else { return }
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, let identity = Self.identity(for: app) else { return }
                self.onActivate?(identity)
            }
        }
        if let app = NSWorkspace.shared.frontmostApplication, let identity = Self.identity(for: app) {
            onActivate?(identity)
        }
    }

    public func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
    }

    public static func identity(for app: NSRunningApplication) -> AppIdentity? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        return AppIdentity(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
