import ApplicationServices
import XCTest
import RoteCore
@testable import RoteAX

/// Scripts one app's answers: each notification gives the queued answers in turn, then `.success`.
/// With `holdsResolutions` a selection stays unresolved until the test calls `release`, standing in
/// for an app that answers the resolver's parent reads slowly (audit L1).
@MainActor
private final class ScriptedConnection: MenuNotificationConnection {
    var answers: [String: [AXError]] = [:]
    var holdsResolutions = false
    private(set) var calls: [String] = []
    private(set) var resolvedBundleIDs: [String] = []
    private var parked: [CheckedContinuation<MenuItemRecord?, Never>] = []

    var pendingResolutions: Int { parked.count }

    func add(_ notification: String) -> AXError {
        calls.append("add \(notification)")
        guard let answer = answers[notification]?.first else { return .success }
        answers[notification]?.removeFirst()
        return answer
    }

    func remove(_ notification: String) {
        calls.append("remove \(notification)")
    }

    func record(for element: AXUIElement, bundleID: String) async -> MenuItemRecord? {
        resolvedBundleIDs.append(bundleID)
        if holdsResolutions {
            return await withCheckedContinuation { parked.append($0) }
        }
        return MenuItemRecord(bundleID: bundleID, path: ["Edit", "Copy"], shortcut: nil)
    }

    /// Answers the oldest held resolution; nil is an item the resolver could not place.
    func release(_ record: MenuItemRecord?) {
        parked.removeFirst().resume(returning: record)
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

    /// Lets the resolution tasks run until nothing is queued, or fails after five seconds.
    private func settle(_ observer: MenuObserver, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while observer.hasQueuedEvents, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertFalse(observer.hasQueuedEvents, "events were still queued", file: file, line: line)
    }

    /// Waits until `connection` holds `count` resolutions.
    private func waitForHeld(_ count: Int, in connection: ScriptedConnection, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while connection.pendingResolutions < count, ContinuousClock.now < deadline { await Task.yield() }
        XCTAssertEqual(connection.pendingResolutions, count, file: file, line: line)
    }

    private let copy = MenuItemRecord(bundleID: "com.apple.Safari", path: ["Edit", "Copy"], shortcut: nil)

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

    func testEachNotificationBecomesItsEvent() async throws {
        let connection = ScriptedConnection()
        let observer = makeObserver(connection)
        let events = EventLog()
        observer.onEvent = { events.append($0) }
        let element = AXUIElementCreateApplication(getpid())
        observer.handle(selected, element: element)                    // not attached: dropped
        try observer.attach(safari)
        for name in [opened, selected, closed, kAXFocusedUIElementChangedNotification] {
            observer.handle(name, element: element)
        }
        await settle(observer)
        XCTAssertEqual(events.events, [.menuOpened, .itemSelected(copy), .menuClosed])
        XCTAssertEqual(connection.resolvedBundleIDs, ["com.apple.Safari"])
    }

    // MARK: Selections resolve off the main actor (audit L1)

    /// The resolver's parent reads no longer run on the main run loop: `handle` returns at once,
    /// and the close that follows a slow selection waits behind it, so the engine still sees
    /// open › selected › closed and classifies the pick as a menu use.
    func testSlowSelectionKeepsEventOrder() async throws {
        let connection = ScriptedConnection()
        connection.holdsResolutions = true
        let observer = makeObserver(connection)
        let events = EventLog()
        observer.onEvent = { events.append($0) }
        try observer.attach(safari)
        let element = AXUIElementCreateApplication(getpid())
        observer.handle(opened, element: element)
        observer.handle(selected, element: element)
        observer.handle(closed, element: element)
        XCTAssertEqual(events.events, [.menuOpened], "the main actor was not blocked, and the close waits behind the selection")
        await waitForHeld(1, in: connection)
        XCTAssertEqual(events.events, [.menuOpened])
        connection.release(copy)
        await settle(observer)
        XCTAssertEqual(events.events, [.menuOpened, .itemSelected(copy), .menuClosed])
    }

    func testTwoSlowSelectionsEmitInNotificationOrder() async throws {
        let connection = ScriptedConnection()
        connection.holdsResolutions = true
        let observer = makeObserver(connection)
        let events = EventLog()
        observer.onEvent = { events.append($0) }
        try observer.attach(safari)
        let element = AXUIElementCreateApplication(getpid())
        observer.handle(selected, element: element)
        observer.handle(selected, element: element)
        observer.handle(closed, element: element)
        await waitForHeld(2, in: connection)
        let paste = MenuItemRecord(bundleID: "com.apple.Safari", path: ["Edit", "Paste"], shortcut: nil)
        connection.release(copy)
        await Task.yield()
        connection.release(paste)
        await settle(observer)
        XCTAssertEqual(events.events, [.itemSelected(copy), .itemSelected(paste), .menuClosed])
    }

    /// An item the resolver cannot place (a context menu, or a read past its deadline) is dropped,
    /// and the events behind it go out.
    func testUnresolvedSelectionIsDroppedAndReleasesTheEventsBehindIt() async throws {
        let connection = ScriptedConnection()
        connection.holdsResolutions = true
        let observer = makeObserver(connection)
        let events = EventLog()
        observer.onEvent = { events.append($0) }
        try observer.attach(safari)
        let element = AXUIElementCreateApplication(getpid())
        observer.handle(opened, element: element)
        observer.handle(selected, element: element)
        observer.handle(closed, element: element)
        await waitForHeld(1, in: connection)
        connection.release(nil)
        await settle(observer)
        XCTAssertEqual(events.events, [.menuOpened, .menuClosed])
    }

    /// A selection still resolving when the app is deactivated belongs to that app: it is dropped
    /// with the rest of the queue, and the next app's events are not held behind it.
    func testDetachDropsPendingSelections() async throws {
        let slow = ScriptedConnection()
        slow.holdsResolutions = true
        let next = ScriptedConnection()
        let observer = makeObserver(slow, next)
        let events = EventLog()
        observer.onEvent = { events.append($0) }
        try observer.attach(safari)
        let element = AXUIElementCreateApplication(getpid())
        observer.handle(selected, element: element)
        observer.handle(closed, element: element)
        await waitForHeld(1, in: slow)
        try observer.attach(notes)
        XCTAssertFalse(observer.hasQueuedEvents)
        observer.handle(opened, element: element)
        XCTAssertEqual(events.events, [.menuOpened], "the new app's events are not held behind the old app's selection")
        slow.release(copy)
        await Task.yield()
        await settle(observer)
        XCTAssertEqual(events.events, [.menuOpened])
    }
}

/// Collects events on the main actor, so a test closure can append without capturing a `var`.
@MainActor
private final class EventLog {
    private(set) var events: [MenuObserverEvent] = []
    func append(_ event: MenuObserverEvent) { events.append(event) }
}
