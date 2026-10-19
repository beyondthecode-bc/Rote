import AppKit

/// Template image drawn in code: a keycap outline, with a slash when paused
/// and a dot badge when Accessibility is missing.
enum MenuBarIcon {
    enum State { case normal, paused, needsPermission }

    @MainActor
    static func image(for state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let key = NSBezierPath(roundedRect: NSRect(x: 2, y: 3.5, width: 14, height: 11), xRadius: 3, yRadius: 3)
            key.lineWidth = 1.5
            key.stroke()

            let legend = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 7.5, width: 5, height: 2), xRadius: 1, yRadius: 1)
            legend.fill()

            switch state {
            case .normal:
                break
            case .paused:
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 3, y: 2))
                slash.line(to: NSPoint(x: 15, y: 16))
                slash.lineWidth = 1.5
                slash.stroke()
            case .needsPermission:
                NSBezierPath(ovalIn: NSRect(x: 11.5, y: 11.5, width: 6, height: 6)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
