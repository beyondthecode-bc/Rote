import ApplicationServices
import Foundation
import XCTest
@testable import Rote
@testable import RoteAX
import RoteCore

/// A throwaway UserDefaults suite. Its name is an absolute path, so CFPreferences keeps it in a
/// plist inside its own temporary directory: never the app's domain, and nothing is left in
/// ~/Library/Preferences (a named suite leaves an empty plist there even after its domain is
/// removed). `remove()` deletes the domain and the directory.
struct TestDefaults: @unchecked Sendable {   // UserDefaults is thread-safe
    let name: String
    let defaults: UserDefaults
    let directory: URL

    init() {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoteTests-defaults-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        name = directory.appendingPathComponent("defaults").path
        defaults = UserDefaults(suiteName: name)!
    }

    func remove() {
        defaults.removePersistentDomain(forName: name)
        try? FileManager.default.removeItem(at: directory)
    }
}

/// A fresh directory under the process's temporary directory; `remove()` deletes it.
struct TemporaryDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RoteTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// Polls `condition` every 5 ms until it holds; fails the test after `timeout`.
@MainActor
func waitUntil(
    timeout: Duration = .seconds(2),
    file: StaticString = #filePath,
    line: UInt = #line,
    _ condition: @MainActor () async -> Bool
) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !(await condition()) {
        guard ContinuousClock.now < deadline else {
            XCTFail("Condition not met within \(timeout)", file: file, line: line)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// Lets queued main-actor tasks run, for asserting that something did NOT happen.
@MainActor
func settle() async {
    try? await Task.sleep(for: .milliseconds(30))
}

/// Serves queued trees per app and records every scan as it starts (`scans`) and as it returns
/// (`finished`). `hold()` parks scans until they are released.
actor FakeScanner: MenuScanning {
    private var queued: [String: [MenuTree]] = [:]
    private(set) var scans: [String] = []
    private(set) var finished: [String] = []
    private var held = false
    private var parked: [(bundleID: String, continuation: CheckedContinuation<Void, Never>)] = []

    func enqueue(_ tree: MenuTree) {
        queued[tree.bundleID, default: []].append(tree)
    }

    func hold() { held = true }

    /// Lets every parked scan finish and stops holding new ones.
    func release() {
        held = false
        let waiting = parked
        parked = []
        for entry in waiting { entry.continuation.resume() }
    }

    /// Lets the parked scans of one app finish; others stay parked.
    func release(_ bundleID: String) {
        let waiting = parked.filter { $0.bundleID == bundleID }
        parked.removeAll { $0.bundleID == bundleID }
        for entry in waiting { entry.continuation.resume() }
    }

    func scanCount(_ bundleID: String) -> Int {
        scans.filter { $0 == bundleID }.count
    }

    func finishedCount(_ bundleID: String) -> Int {
        finished.filter { $0 == bundleID }.count
    }

    func scan(app: AppIdentity) async -> MenuTree {
        scans.append(app.bundleID)
        if held {
            await withCheckedContinuation { parked.append((app.bundleID, $0)) }
        }
        var trees = queued[app.bundleID] ?? []
        let tree = trees.isEmpty
            ? MenuTree(bundleID: app.bundleID, appName: app.name, menus: [], scannedAt: Date(), isPartial: false)
            : trees.removeFirst()
        queued[app.bundleID] = trees
        finished.append(app.bundleID)
        return tree
    }
}

/// Stands in for a live AXObserver: every registration succeeds and nothing reaches Accessibility.
final class FakeMenuConnection: MenuNotificationConnection {
    func add(_ notification: String) -> AXError { .success }
    func remove(_ notification: String) {}
    func record(for element: AXUIElement, bundleID: String) -> MenuItemRecord? { nil }
    func close() {}
}

@MainActor
func makeFakeObserver() -> MenuObserver {
    MenuObserver(retryDelays: []) { _, _ in FakeMenuConnection() }
}

enum Fixtures {
    static let appA = AppIdentity(pid: 90_001, bundleID: "com.example.Alpha", name: "Alpha")
    static let appB = AppIdentity(pid: 90_002, bundleID: "com.example.Beta", name: "Beta")
    static let ownApp = AppIdentity(pid: 90_003, bundleID: "com.beyondthecode.rote", name: "Rote")

    static func item(_ path: [String], _ key: String) -> MenuItemRecord {
        item(appA, path, key)
    }

    static func item(_ app: AppIdentity, _ path: [String], _ key: String) -> MenuItemRecord {
        MenuItemRecord(bundleID: app.bundleID, path: path, shortcut: Shortcut(modifiers: [.command], key: .character(key)))
    }

    static func menu(_ title: String, _ items: [MenuItemRecord], complete: Bool = true) -> MenuTree.Menu {
        MenuTree.Menu(title: title, isAppleMenu: false, items: items, isComplete: complete)
    }

    static func tree(_ menus: [MenuTree.Menu], partial: Bool = false) -> MenuTree {
        tree(appA, menus, partial: partial)
    }

    static func tree(_ app: AppIdentity, _ menus: [MenuTree.Menu], partial: Bool = false) -> MenuTree {
        MenuTree(bundleID: app.bundleID, appName: app.name, menus: menus, scannedAt: Date(), isPartial: partial)
    }

    /// ⌘ plus a letter, as the key monitor reports it on a Latin layout.
    static func commandPress(_ letter: String, keyCode: UInt16, isRepeat: Bool = false) -> KeyPress {
        KeyPress(characters: letter, commandCharacters: letter, keyCode: keyCode, modifiers: [.command], isRepeat: isRepeat)
    }
}
