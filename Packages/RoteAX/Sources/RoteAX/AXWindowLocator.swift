import AppKit
import ApplicationServices

/// Finds the screen that holds an app's focused window, so panels appear where the user is looking.
public enum AXWindowLocator {
    /// Frame of `pid`'s focused window in AppKit screen coordinates (origin at the
    /// bottom-left of the primary display), or nil when the app has no focused window.
    @MainActor
    public static func focusedWindowFrame(pid: pid_t) -> CGRect? {
        let application = AXUIElementCreateApplication(pid)
        guard let window = AXReader.element(application, kAXFocusedWindowAttribute),
              let positionValue = AXReader.value(window, kAXPositionAttribute),
              let sizeValue = AXReader.value(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              let primary = NSScreen.screens.first
        else { return nil }
        return appKitFrame(position: position, size: size, primaryScreenFrame: primary.frame)
    }

    @MainActor
    public static func screen(containing rect: CGRect) -> NSScreen? {
        let screens = NSScreen.screens
        return index(ofFrameContaining: rect, in: screens.map(\.frame)).map { screens[$0] }
    }

    /// Accessibility coordinates start at the top-left of the primary display, AppKit's at its bottom-left.
    static func appKitFrame(position: CGPoint, size: CGSize, primaryScreenFrame: CGRect) -> CGRect {
        CGRect(x: position.x, y: primaryScreenFrame.maxY - position.y - size.height, width: size.width, height: size.height)
    }

    /// The first frame that holds the center of `rect`.
    static func index(ofFrameContaining rect: CGRect, in frames: [CGRect]) -> Int? {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        return frames.firstIndex { $0.contains(center) }
    }
}
