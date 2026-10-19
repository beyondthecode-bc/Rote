import ApplicationServices
import XCTest
import RoteCore
@testable import RoteAX

/// Scripts one app's answers: each notification gives the queued answers in turn, then `.success`.
private final class ScriptedConnection: MenuNotificationConnection {
    var answers: [String: [AXError]] = [:]
    private(set) var calls: [String] = []
    private(set) var resolvedBundleIDs: [String] = []

    func add(_ notification: String) -> AXError {
        calls.append("add \(notification)")
        guard let answer = answers[notification]?.first else { return .success }
        answers[notification]?.removeFirst()
        return answer
    }

    func remove(_ notification: String) {
        calls.append("remove \(notification)")
    }

    func record(for element: AXUIElement, bundleID: String) -> MenuItemRecord? {
        resolvedBundleIDs.append(bundleID)
        return MenuItemRecord(bundleID: bundleID, path: ["Edit", "Copy"], shortcut: nil)
    }

    func close() {
        calls.append("close")
    }
}

@MainActor
final class MenuObserverTests: XCTestCase {
    private let safari = AppIdentity(pid: 1, bundleID: "com.apple.Safari", name: "Safari")
    private let notes = AppIdentity(pid: 2, bundleID: "com.apple.Notes", name: "Notes")
    private let closed = kAXMenuClosedNotification
    private let opened = kAXMenuOpenedNotification
    private let selected = kAXMenuItemSelectedNotification

    private func makeObserver(_ connections: ScriptedConnection..., retries: Int = 2) -> MenuObserver {
        var queue = connections
        return MenuObserver(retryDelays: Array(repeating: .zero, count: retries)) { _, _ in queue.removeFirst() }
    }

    /// Runs the scheduled retries, each of which may schedule the next.
    private func drainRetries(_ observer: MenuObserver) async {
        while let task = observer.retryTask { await task.value }
    }

    func testAttachRegistersAllThreeAndDetachRemovesThem() throws {
        let connection = ScriptedConnection()
        let observer = makeObserver(connection)
        try observer.attach(safari)
        XCTAssertEqual(observer.attachedApp, safari)
        XCTAssertNil(observer.retryTask)
        observer.detach()
        XCTAssertNil(observer.attachedApp)
        XCTAssertEqual(connection.calls, [
            "add \(closed)", "add \(opened)", "add \(selected)",
            "close", "remove \(closed)", "remove \(opened)", "remove \(selected)",
        ])
    }

    func testAlreadyRegisteredCountsAsRegistered() throws {
        let connection = ScriptedConnection()
        connection.answers[opened] = [.notificationAlreadyRegistered]
        let observer = makeObserver(connection)
        try observer.attach(safari)
        XCTAssertEqual(observer.attachedApp, safari)
        XCTAssertNil(observer.retryTask)
    }

    /// Spec §11: an app busy at activation answers `.cannotComplete`. The observer keeps what
    /// registered, sends nothing more to the busy app on that try, and retries the rest.
    func testBusyAppIsRetriedUntilItAnswers() async throws {
        let connection = ScriptedConnection()
        connection.answers[opened] = [.cannotComplete, .cannotComplete]
        let observer = makeObserver(connection)
        try observer.attach(safari)
        XCTAssertEqual(observer.attachedApp, safari)
        XCTAssertEqual(connection.calls, ["add \(closed)", "add \(opened)"])
        await drainRetries(observer)
        XCTAssertEqual(connection.calls, ["add \(closed)", "add \(opened)", "add \(opened)", "add \(opened)", "add \(selected)"])
        observer.detach()
        XCTAssertEqual(connection.calls.suffix(4), ["close", "remove \(closed)", "remove \(opened)", "remove \(selected)"])
    }

    func testRetriesStopAfterTheLastDelay() async throws {
        let connection = ScriptedConnection()
        connection.answers[closed] = Array(repeating: .cannotComplete, count: 10)
        let observer = makeObserver(connection, retries: 3)
        try observer.attach(safari)
        await drainRetries(observer)
        XCTAssertEqual(connection.calls, Array(repeating: "add \(closed)", count: 4))
        XCTAssertEqual(observer.attachedApp, safari)
        observer.detach()
        XCTAssertEqual(connection.calls.last, "close", "nothing registered, nothing to remove")
    }

    func testDetachCancelsAPendingRetry() async throws {
        let connection = ScriptedConnection()
        connection.answers[closed] = [.cannotComplete]
        let observer = MenuObserver(retryDelays: [.milliseconds(20)]) { _, _ in connection }
        try observer.attach(safari)
        let pending = try XCTUnwrap(observer.retryTask)
        observer.detach()
        await pending.value
        XCTAssertNil(observer.retryTask)
        XCTAssertEqual(connection.calls, ["add \(closed)", "close"])
    }

    func testAttachingTheNextAppCancelsTheLastAppsRetry() async throws {
        let busy = ScriptedConnection()
        busy.answers[closed] = [.cannotComplete]
        let next = ScriptedConnection()
        let observer = makeObserver(busy, next)
        try observer.attach(safari)
        let pending = try XCTUnwrap(observer.retryTask)
        try observer.attach(notes)
        await pending.value
        XCTAssertEqual(busy.calls, ["add \(closed)", "close"])
        XCTAssertEqual(next.calls, ["add \(closed)", "add \(opened)", "add \(selected)"])
        XCTAssertEqual(observer.attachedApp, notes)
    }

    /// Any other failure (trust revoked, app gone, notification unsupported) is not retried:
    /// attach throws and leaves nothing registered.
    func testOtherFailuresThrowAndUndoTheRegistrations() {
        let connection = ScriptedConnection()
        connection.answers[opened] = [.apiDisabled]
        let observer = makeObserver(connection)
        XCTAssertThrowsError(try observer.attach(safari)) { error in
            XCTAssertEqual(error as? MenuObserverError, .registrationFailed(notification: self.opened, code: AXError.apiDisabled.rawValue))
        }
        XCTAssertNil(observer.attachedApp)
        XCTAssertEqual(connection.calls, ["add \(closed)", "add \(opened)", "close", "remove \(closed)"])
    }

    func testOtherFailureDuringARetryDetaches() async throws {
        let connection = ScriptedConnection()
        connection.answers[opened] = [.cannotComplete, .invalidUIElement]
        let observer = makeObserver(connection)
        try observer.attach(safari)
        await drainRetries(observer)
        XCTAssertNil(observer.attachedApp)
        XCTAssertEqual(connection.calls, ["add \(closed)", "add \(opened)", "add \(opened)", "close", "remove \(closed)"])
    }

    func testCreateFailureThrows() {
        let observer = MenuObserver(retryDelays: []) { _, _ in throw MenuObserverError.createFailed(AXError.failure.rawValue) }
        XCTAssertThrowsError(try observer.attach(safari)) { error in
            XCTAssertEqual(error as? MenuObserverError, .createFailed(AXError.failure.rawValue))
        }
        XCTAssertNil(observer.attachedApp)
    }

    func testEachNotificationBecomesItsEvent() throws {
        let connection = ScriptedConnection()
        let observer = makeObserver(connection)
        var events: [MenuObserverEvent] = []
        observer.onEvent = { events.append($0) }
        let element = AXUIElementCreateApplication(getpid())
        observer.handle(selected, element: element)                    // not attached: dropped
        try observer.attach(safari)
        for name in [opened, selected, closed, kAXFocusedUIElementChangedNotification] {
            observer.handle(name, element: element)
        }
        XCTAssertEqual(events, [
            .menuOpened,
            .itemSelected(MenuItemRecord(bundleID: "com.apple.Safari", path: ["Edit", "Copy"], shortcut: nil)),
            .menuClosed,
        ])
        XCTAssertEqual(connection.resolvedBundleIDs, ["com.apple.Safari"])
    }
}
