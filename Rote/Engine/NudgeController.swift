import AppKit
import OSLog
import RoteAX
import RoteCore
import SwiftUI

/// Shows one nudge at a time (spec §7.1): placement, timing, hover pause, VoiceOver, sound.
@MainActor
final class NudgeController {
    var onDismiss: (() -> Void)?
    var onSnooze: ((String) -> Void)?
    var onMute: ((String) -> Void)?
    var onPauseHour: (() -> Void)?

    private let settings: AppSettings
    private let panel = NudgePanel()
    private var current: ItemRecord?
    private var dismissTask: Task<Void, Never>?

    init(settings: AppSettings) {
        self.settings = settings
    }

    var isShowing: Bool { current != nil }

    func show(_ record: ItemRecord, appName: String, appIcon: NSImage?) {
        dismissTask?.cancel()
        current = record

        let model = NudgeModel(record: record, appName: appName, appIcon: appIcon, pointerAtShow: NSEvent.mouseLocation)
        let view = NudgeView(model: model, controller: self)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host
        panel.setContentSize(size)

        let screen = Self.targetScreen()
        // The card sits `hudTopInset` below the menu bar; the host adds `hudShadowPadding` around the card.
        let hostMaxY = screen.visibleFrame.maxY - DesignTokens.hudTopInset + DesignTokens.hudShadowPadding
        let origin = NSPoint(x: screen.frame.midX - size.width / 2, y: hostMaxY - size.height)
        panel.setFrameOrigin(origin)

        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.12 : 0.18
            panel.animator().alphaValue = 1
        }

        announce(record)
        if settings.soundEnabled { NSSound(named: "Tink")?.play() }
        scheduleDismiss()
    }

    func setHovering(_ isHovering: Bool) {
        if isHovering {
            dismissTask?.cancel()
            dismissTask = nil
        } else if current != nil {
            scheduleDismiss()
        }
    }

    func snoozeCurrent() {
        guard let current else { return }
        onSnooze?(current.identity)
        dismiss()
    }

    func muteCurrent() {
        guard let current else { return }
        onMute?(current.identity)
        dismiss()
    }

    func pauseForAnHour() {
        onPauseHour?()
        dismiss()
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard current != nil else { return }
        current = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.25
            panel.animator().alphaValue = 0
        }
        let panel = self.panel
        Task {
            try? await Task.sleep(for: .milliseconds(260))
            if self.current == nil { panel.orderOut(nil) }
        }
        onDismiss?()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let duration = settings.hudDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled, let self else { return }
            self.dismiss()
        }
    }

    /// Screen holding the frontmost app's focused window, else the main screen.
    static func targetScreen() -> NSScreen {
        if let app = NSWorkspace.shared.frontmostApplication,
           app.bundleIdentifier != Bundle.main.bundleIdentifier,
           let frame = AXWindowLocator.focusedWindowFrame(pid: app.processIdentifier),
           let screen = AXWindowLocator.screen(containing: frame) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    private func announce(_ record: ItemRecord) {
        guard let shortcut = record.item.shortcut else { return }
        let text = l("nudge.announcement", record.item.title, GlyphFormatter.spokenDescription(shortcut))
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }
}
