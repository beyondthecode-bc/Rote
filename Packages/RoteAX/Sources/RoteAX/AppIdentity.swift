import Foundation

/// A running app as the engine sees it. Value type so it can cross actors.
public struct AppIdentity: Sendable, Hashable {
    public let pid: pid_t
    public let bundleID: String
    public let name: String

    public init(pid: pid_t, bundleID: String, name: String) {
        self.pid = pid
        self.bundleID = bundleID
        self.name = name
    }
}
