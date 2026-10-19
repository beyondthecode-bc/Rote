import Foundation

/// Pairs each key press the key monitor matched with the menu-item-selected notification the app
/// posts for the same key equivalent, so one press is one shortcut use (spec §5.5, §11).
///
/// AppKit posts that notification for every key equivalent, with no menu opened, but only once
/// the app's action returns: a slow action delays it by seconds, and quick presses (⌘A ⌘C) both
/// arrive before either notification. So each press waits up to `echoTimeout` for one
/// notification of the same item, or of the same shortcut in the same app (a title such as
/// "Undo Typing" can change after the scan). A counted notification that arrives before its press
/// waits `earlyEchoWindow` for it. Presses never pair with each other: ⌘Z ⌘Z ⌘Z is three uses.
/// Times are monotonic, so a clock change cannot stretch or close a window.
public struct ShortcutEchoFilter: Sendable {
    public static let echoTimeout: Duration = .seconds(5)
    public static let earlyEchoWindow: Duration = .milliseconds(300)

    private struct Use: Sendable {
        let item: MenuItemRecord
        let at: ContinuousClock.Instant

        func pairs(with other: MenuItemRecord) -> Bool {
            if item.identity == other.identity { return true }
            guard let shortcut = item.shortcut else { return false }
            return item.bundleID == other.bundleID && shortcut == other.shortcut
        }
    }

    /// Counted presses whose notification has not arrived yet, oldest first.
    private var pressesAwaitingEcho: [Use] = []
    /// Counted selections whose key press has not arrived yet, oldest first.
    private var selectionsAwaitingPress: [Use] = []

    public init() {}

    /// A key press matched `item`. False when it is the press behind a selection already counted;
    /// otherwise the press counts and waits for its notification.
    public mutating func keyPressMatched(_ item: MenuItemRecord, at now: ContinuousClock.Instant) -> Bool {
        expire(at: now)
        if let index = selectionsAwaitingPress.firstIndex(where: { $0.pairs(with: item) }) {
            selectionsAwaitingPress.remove(at: index)
            return false
        }
        pressesAwaitingEcho.append(Use(item: item, at: now))
        return true
    }

    /// The app reported `item` selected. True when it is the notification of a press already
    /// counted, which the caller drops.
    public mutating func isEcho(_ item: MenuItemRecord, at now: ContinuousClock.Instant) -> Bool {
        expire(at: now)
        guard let index = pressesAwaitingEcho.firstIndex(where: { $0.pairs(with: item) }) else { return false }
        pressesAwaitingEcho.remove(at: index)
        return true
    }

    /// A selection with no menu involved was counted as a shortcut use; its press may still come.
    public mutating func selectionCounted(_ item: MenuItemRecord, at now: ContinuousClock.Instant) {
        expire(at: now)
        selectionsAwaitingPress.append(Use(item: item, at: now))
    }

    /// Forgets everything pending. Call when another app activates, and when a menu opens: the app
    /// has posted every notification for earlier presses by then, so a later selection is a pick.
    public mutating func reset() {
        pressesAwaitingEcho.removeAll()
        selectionsAwaitingPress.removeAll()
    }

    private mutating func expire(at now: ContinuousClock.Instant) {
        pressesAwaitingEcho.removeAll { $0.at.duration(to: now) > Self.echoTimeout }
        selectionsAwaitingPress.removeAll { $0.at.duration(to: now) > Self.earlyEchoWindow }
    }
}
