import AppKit
import XCTest
@testable import Rote
import RoteCore

/// Synthesized NSEvents through `KeyEventMonitor.handle`. The monitors themselves are never installed.
@MainActor
final class KeyEventMonitorTests: XCTestCase {
    private var received: [KeyEventMonitor.Event] = []

    private func makeMonitor() -> KeyEventMonitor {
        received = []
        let monitor = KeyEventMonitor()
        monitor.onEvent = { [weak self] event in self?.received.append(event) }
        return monitor
    }

    private func keyEvent(
        _ characters: String,
        keyCode: UInt16,
        flags: NSEvent.ModifierFlags,
        isRepeat: Bool = false,
        type: NSEvent.EventType = .keyDown
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type, location: .zero, modifierFlags: flags, timestamp: 0, windowNumber: 0, context: nil,
            characters: characters, charactersIgnoringModifiers: characters, isARepeat: isRepeat, keyCode: keyCode
        ))
    }

    private func mouseEvent(_ type: CGEventType, button: CGMouseButton) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: .zero, mouseButton: button))
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    /// A scroll event with the raw CoreGraphics phases: 1 began, 2 changed, 4 ended, 8 cancelled,
    /// 128 may-begin; momentum 1 begin, 2 continue, 3 end.
    private func scrollEvent(phase: Int64 = 0, momentum: Int64 = 0) throws -> NSEvent {
        let cgEvent = try XCTUnwrap(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -4, wheel2: 0, wheel3: 0))
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
        return try XCTUnwrap(NSEvent(cgEvent: cgEvent))
    }

    // MARK: Key presses

    func testACommandPressCarriesTheLayoutsCommandCharacters() throws {
        let monitor = makeMonitor()
        let event = try keyEvent("s", keyCode: 1, flags: [.command])

        monitor.handle(event, inOwnApp: false)

        let commandCharacters = try XCTUnwrap(event.characters(byApplyingModifiers: .command))
        XCTAssertFalse(commandCharacters.isEmpty)
        XCTAssertEqual(received, [.keyDown(KeyPress(
            characters: "s", commandCharacters: commandCharacters, keyCode: 1, modifiers: [.command], isRepeat: false
        ), inOwnApp: false)])
    }

    func testWithoutCommandTheCommandCharactersStayEmpty() throws {
        let monitor = makeMonitor()
        monitor.handle(try keyEvent("s", keyCode: 1, flags: [.control, .option]), inOwnApp: false)

        XCTAssertEqual(received, [.keyDown(KeyPress(
            characters: "s", commandCharacters: "", keyCode: 1, modifiers: [.control, .option], isRepeat: false
        ), inOwnApp: false)])
    }

    func testAnAutoRepeatIsMarkedAsARepeat() throws {
        let monitor = makeMonitor()
        monitor.handle(try keyEvent("s", keyCode: 1, flags: [.control], isRepeat: true), inOwnApp: false)
        monitor.handle(try keyEvent("s", keyCode: 1, flags: [.control], isRepeat: false), inOwnApp: false)

        guard received.count == 2,
              case .keyDown(let first, _) = received[0],
              case .keyDown(let second, _) = received[1]
        else { return XCTFail("expected two key presses, got \(received)") }
        XCTAssertTrue(first.isRepeat)
        XCTAssertFalse(second.isRepeat)
    }

    func testPressesInRotesOwnWindowsAreTaggedAsSuch() throws {
        let monitor = makeMonitor()
        monitor.handle(try keyEvent("s", keyCode: 1, flags: [.control]), inOwnApp: true)
        monitor.handle(try keyEvent("s", keyCode: 1, flags: [.control]), inOwnApp: false)

        let tags: [Bool] = received.compactMap {
            if case .keyDown(_, let inOwnApp) = $0 { return inOwnApp }
            return nil
        }
        XCTAssertEqual(tags, [true, false])
    }

    // MARK: Modifiers

    func testOnlyTheFourCoachModifiersAreKept() {
        XCTAssertEqual(KeyEventMonitor.modifiers(from: [.control]), [.control])
        XCTAssertEqual(KeyEventMonitor.modifiers(from: [.option]), [.option])
        XCTAssertEqual(KeyEventMonitor.modifiers(from: [.shift]), [.shift])
        XCTAssertEqual(KeyEventMonitor.modifiers(from: [.command]), [.command])
        XCTAssertEqual(KeyEventMonitor.modifiers(from: [.capsLock, .function, .numericPad, .help]), [])
        XCTAssertEqual(
            KeyEventMonitor.modifiers(from: [.control, .option, .shift, .command, .capsLock, .function]),
            [.control, .option, .shift, .command]
        )
    }

    func testAModifierChangeIsReported() throws {
        let monitor = makeMonitor()
        monitor.handle(try keyEvent("", keyCode: 55, flags: [.command], type: .flagsChanged), inOwnApp: false, mouseButtonsDown: false)
        XCTAssertEqual(received, [.flagsChanged(modifiers: [.command])])
    }

    func testAModifierChangeMidDragAlsoCancelsLikeAClick() throws {
        let monitor = makeMonitor()
        monitor.handle(try keyEvent("", keyCode: 58, flags: [.option], type: .flagsChanged), inOwnApp: false, mouseButtonsDown: true)
        XCTAssertEqual(received, [.flagsChanged(modifiers: [.option]), .mouseDown])
    }

    // MARK: Pointer

    func testButtonPressesAndDragsCancel() throws {
        let monitor = makeMonitor()
        let events: [(CGEventType, CGMouseButton)] = [
            (.leftMouseDown, .left), (.rightMouseDown, .right), (.otherMouseDown, .center),
            (.leftMouseDragged, .left), (.rightMouseDragged, .right), (.otherMouseDragged, .center),
        ]
        for (type, button) in events {
            monitor.handle(try mouseEvent(type, button: button), inOwnApp: false)
        }
        XCTAssertEqual(received, Array(repeating: .mouseDown, count: events.count))
    }

    func testAWheelTickOrAMovingTrackpadScrollInAnotherAppCancels() throws {
        let monitor = makeMonitor()
        let tick = try scrollEvent()
        let began = try scrollEvent(phase: 1)
        let changed = try scrollEvent(phase: 2)
        XCTAssertEqual(began.phase, .began)
        XCTAssertEqual(changed.phase, .changed)

        for event in [tick, began, changed] { monitor.handle(event, inOwnApp: false) }

        XCTAssertEqual(received, [.mouseDown, .mouseDown, .mouseDown])
    }

    func testMomentumAndFingersRestingOrLiftingDoNotCancel() throws {
        let monitor = makeMonitor()
        let momentum = try [1, 2, 3].map { try scrollEvent(momentum: $0) }
        XCTAssertEqual(momentum.map(\.momentumPhase), [.began, .changed, .ended])
        let ended = try scrollEvent(phase: 4)
        let cancelled = try scrollEvent(phase: 8)
        let mayBegin = try scrollEvent(phase: 128)
        XCTAssertEqual(ended.phase, .ended)
        XCTAssertEqual(cancelled.phase, .cancelled)
        XCTAssertEqual(mayBegin.phase, .mayBegin)

        for event in momentum + [ended, cancelled, mayBegin] { monitor.handle(event, inOwnApp: false) }

        XCTAssertEqual(received, [])
    }

    func testScrollingRotesOwnSheetDoesNotCancel() throws {
        let monitor = makeMonitor()
        monitor.handle(try scrollEvent(), inOwnApp: true)
        monitor.handle(try scrollEvent(phase: 1), inOwnApp: true)
        monitor.handle(try scrollEvent(phase: 2), inOwnApp: true)
        XCTAssertEqual(received, [])
    }
}
