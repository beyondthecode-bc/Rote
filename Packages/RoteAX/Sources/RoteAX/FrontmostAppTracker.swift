import AppKit

/// Reports the frontmost app on start and on every activation. An app without an `AppIdentity`
/// (no bundle ID) is reported as nil, so the consumer stops treating the previous app as frontmost (spec §4.3).
@MainActor
public final class FrontmostAppTracker {
    public var onActivate: ((AppIdentity?) -> Void)?
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
                guard let self else { return }
                self.onActivate?(app.flatMap(Self.identity(for:)))
            }
        }
        onActivate?(NSWorkspace.shared.frontmostApplication.flatMap(Self.identity(for:)))
    }

    public func stop() {
        if let token { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        token = nil
    }

    /// Reads only fixed properties of a Sendable value, so it needs no actor.
    nonisolated public static func identity(for app: NSRunningApplication) -> AppIdentity? {
        guard let bundleID = app.bundleIdentifier else { return nil }
        return AppIdentity(pid: app.processIdentifier, bundleID: bundleID, name: app.localizedName ?? bundleID)
    }
}
