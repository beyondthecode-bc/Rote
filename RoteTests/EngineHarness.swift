import Foundation
import XCTest
@testable import Rote
@testable import RoteAX
import RoteCore

/// A `CoachEngine` with every dependency faked or redirected: a scripted scanner, an observer that
/// never reaches Accessibility, a tracker and key monitor that are never started, a state file in a
/// temporary directory and a throwaway defaults suite. Events go in through the same callbacks the
/// engine installs on its real dependencies in `start()`.
@MainActor
final class EngineHarness {
    let testDefaults = TestDefaults()
    let directory: TemporaryDirectory
    let scanner = FakeScanner()
    let tracker = FrontmostAppTracker()
    let observer = makeFakeObserver()
    let keyMonitor = KeyEventMonitor()
    let store: StateStore
    let settings: AppSettings
    let engine: CoachEngine
    private(set) var nudges: [ItemRecord] = []
    private(set) var keyEvents: [KeyEventMonitor.Event] = []

    var defaults: UserDefaults { testDefaults.defaults }
    var stateURL: URL { directory.url.appendingPathComponent("state.json") }

    init(menuCloseGrace: Duration = .milliseconds(300), pruneInterval: TimeInterval = 86_400) throws {
        directory = try TemporaryDirectory()
        let stateURL = directory.url.appendingPathComponent("state.json")
        store = StateStore(fileURL: stateURL, debounce: .milliseconds(10))
        settings = AppSettings(defaults: testDefaults.defaults)
        engine = CoachEngine(
            settings: settings,
            scanner: scanner,
            tracker: tracker,
            observer: observer,
            keyMonitor: keyMonitor,
            store: store,
            defaults: testDefaults.defaults,
            isTrusted: { false },
            menuCloseGrace: menuCloseGrace,
            pruneInterval: pruneInterval
        )
        engine.onNudge = { [weak self] record in self?.nudges.append(record) }
        engine.onKeyEvent = { [weak self] event in self?.keyEvents.append(event) }
    }

    func cleanup() {
        testDefaults.remove()
        directory.remove()
    }

    /// Lets queued saves reach the store, writes them, then deletes everything: a debounced save
    /// that fired after the directory was gone would create it again.
    func tearDown() async {
        await settle()
        await store.flush()
        cleanup()
    }

    /// Writes `state` where the engine's store will load it from, through a separate store.
    func save(_ state: CoachState) async throws {
        try await StateStore(fileURL: stateURL).saveNow(state)
    }

    /// What is on disk now, read through a separate store.
    func savedState() async -> CoachState? {
        if case .loaded(let state) = await StateStore(fileURL: stateURL).load() { return state }
        return nil
    }

    // MARK: Events, through the callbacks `start()` installs

    func activate(_ app: AppIdentity?) {
        tracker.onActivate?(app)
    }

    /// Activates `app` and waits until the scan that serves `tree` is the current tree.
    func activate(_ app: AppIdentity, serving tree: MenuTree, file: StaticString = #filePath, line: UInt = #line) async {
        await scanner.enqueue(tree)
        activate(app)
        await waitUntil(file: file, line: line) { self.engine.currentTree == tree }
    }

    func send(_ event: MenuObserverEvent) {
        observer.onEvent?(event)
    }

    /// A pick with the mouse: the menu opens, the item is chosen, the menu closes.
    func menuPick(_ item: MenuItemRecord) {
        send(.menuOpened)
        send(.itemSelected(item))
        send(.menuClosed)
    }

    func press(_ press: KeyPress, inOwnApp: Bool = false) {
        keyMonitor.onEvent?(.keyDown(press, inOwnApp: inOwnApp))
    }

    func record(_ item: MenuItemRecord) -> ItemRecord? {
        engine.state.items[item.identity]
    }

    /// Three mouse picks: the item is nudged and goes into coaching. The nudge is then dismissed.
    func coach(_ item: MenuItemRecord, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<3 { menuPick(item) }
        XCTAssertEqual(nudges.last?.identity, item.identity, "the third pick nudges", file: file, line: line)
        XCTAssertEqual(record(item)?.phase, .coaching, file: file, line: line)
        engine.nudgeDismissed()
    }
}
