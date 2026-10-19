import AppKit

/// Template image drawn in code: a keycap outline, with a slash when paused
/// and an exclamation badge when Accessibility is missing. Its accessibility description
/// names the state: the status item's VoiceOver title comes only from it.
enum MenuBarIcon {
    enum State { case normal, paused, needsPermission }

    @MainActor
    static func image(for state: State) -> NSImage {
        // @Sendable: AppKit may run the handler on whatever thread draws the image.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { @Sendable _ in
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
                // An exclamation badge, cut free of the keycap's corner so the two never merge.
                let context = NSGraphicsContext.current
                context?.compositingOperation = .clear
                NSBezierPath(ovalIn: NSRect(x: 8.75, y: 8.75, width: 10.5, height: 10.5)).fill()
                context?.compositingOperation = .sourceOver
                NSBezierPath(ovalIn: NSRect(x: 10, y: 10, width: 8, height: 8)).fill()
                context?.compositingOperation = .clear
                NSBezierPath(roundedRect: NSRect(x: 13.25, y: 13.25, width: 1.5, height: 3.25), xRadius: 0.75, yRadius: 0.75).fill()
                NSBezierPath(ovalIn: NSRect(x: 13.25, y: 11.25, width: 1.5, height: 1.5)).fill()
                context?.compositingOperation = .sourceOver
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = switch state {
        case .normal: l("app.name")
        case .paused: l("menubar.paused")
        case .needsPermission: l("permission.title")
        }
        return image
    }
}
