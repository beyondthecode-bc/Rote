import AppKit
import RoteCore

/// Global (other apps) and local (Rote's own windows) NSEvent monitors.
/// Global monitors deliver events only while Accessibility is trusted.
@MainActor
final class KeyEventMonitor {
    enum Event: Equatable {
        /// A key press, auto-repeats included (`KeyPress.isRepeat`): a key held before ⌘ cancels the
        /// hold, but a repeat matches no shortcut. `inOwnApp` marks presses typed into Rote's own
        /// windows, which are never shortcut uses in another app.
        case keyDown(KeyPress, inOwnApp: Bool)
        case flagsChanged(modifiers: Modifiers)
        /// Pointer activity that cancels a hold: a button press, a drag, a modifier change made
        /// while a button is down, or a wheel tick or moving trackpad scroll in another app (Rote's
        /// sheet scrolls under a hold). Momentum after a flick, and fingers resting on or lifting off
        /// the trackpad, do not cancel.
        case mouseDown
    }

    var onEvent: ((Event) -> Void)?

    private var globalToken: Any?
    private var localToken: Any?

    static let mask: NSEvent.EventTypeMask = [
        .keyDown, .flagsChanged,
        .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .scrollWheel,
    ]

    func start() {
        guard globalToken == nil else { return }
        globalToken = NSEvent.addGlobalMonitorForEvents(matching: Self.mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, inOwnApp: false) }
        }
        localToken = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event, inOwnApp: true) }
            return event
        }
    }

    func stop() {
        if let globalToken { NSEvent.removeMonitor(globalToken) }
        if let localToken { NSEvent.removeMonitor(localToken) }
        globalToken = nil
        localToken = nil
    }

    /// `mouseButtonsDown` is read only for a modifier change; tests pass it explicitly.
    func handle(_ event: NSEvent, inOwnApp: Bool, mouseButtonsDown: @autoclosure () -> Bool = NSEvent.pressedMouseButtons != 0) {
        switch event.type {
        case .keyDown:
            let modifiers = Self.modifiers(from: event.modifierFlags)
            onEvent?(.keyDown(KeyPress(
                characters: event.charactersIgnoringModifiers ?? "",
                commandCharacters: modifiers.contains(.command) ? event.characters(byApplyingModifiers: .command) ?? "" : "",
                keyCode: event.keyCode,
                modifiers: modifiers,
                isRepeat: event.isARepeat
            ), inOwnApp: inOwnApp))
        case .flagsChanged:
            onEvent?(.flagsChanged(modifiers: Self.modifiers(from: event.modifierFlags)))
            // ⌥ or ⌘ pressed mid-drag (Finder copy, move between volumes) must not open the sheet.
            if mouseButtonsDown() { onEvent?(.mouseDown) }
        case .scrollWheel:
            let isMoving = event.phase.isEmpty || event.phase == .began || event.phase == .changed
            if !inOwnApp && isMoving && event.momentumPhase.isEmpty { onEvent?(.mouseDown) }
        default:
            onEvent?(.mouseDown)
        }
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Modifiers {
        var result: Modifiers = []
        if flags.contains(.control) { result.insert(.control) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.command) { result.insert(.command) }
        return result
    }
}
