import AppKit
import RoteCore

/// Global (other apps) and local (Rote's own windows) NSEvent monitors.
/// Global monitors deliver events only while Accessibility is trusted.
@MainActor
final class KeyEventMonitor {
    enum Event {
        case keyDown(characters: String, keyCode: UInt16, modifiers: Modifiers)
        case flagsChanged(modifiers: Modifiers)
        case mouseDown
    }

    var onEvent: ((Event) -> Void)?

    private var globalToken: Any?
    private var localToken: Any?

    private static let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown, .otherMouseDown]

    func start() {
        guard globalToken == nil else { return }
        globalToken = NSEvent.addGlobalMonitorForEvents(matching: Self.mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        localToken = NSEvent.addLocalMonitorForEvents(matching: Self.mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
            return event
        }
    }

    func stop() {
        if let globalToken { NSEvent.removeMonitor(globalToken) }
        if let localToken { NSEvent.removeMonitor(localToken) }
        globalToken = nil
        localToken = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .keyDown:
            onEvent?(.keyDown(
                characters: event.charactersIgnoringModifiers ?? "",
                keyCode: event.keyCode,
                modifiers: Self.modifiers(from: event.modifierFlags)
            ))
        case .flagsChanged:
            onEvent?(.flagsChanged(modifiers: Self.modifiers(from: event.modifierFlags)))
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
