import ApplicationServices
import Foundation
import RoteCore

public enum MenuObserverEvent: Sendable, Equatable {
    case menuOpened
    case menuClosed
    case itemSelected(MenuItemRecord)
}

public enum MenuObserverError: Error, Equatable {
    case createFailed(Int32)
    case registrationFailed(notification: String, code: Int32)
}

/// Listens to one app's menu notifications (spec §4.3). Attach on activation, detach on deactivation.
@MainActor
public final class MenuObserver {
    public var onEvent: ((MenuObserverEvent) -> Void)?

    private var observer: AXObserver?
    private var appElement: AXUIElement?
    private var app: AppIdentity?

    private static let notifications: [String] = [
        kAXMenuOpenedNotification, kAXMenuClosedNotification, kAXMenuItemSelectedNotification,
    ]

    public init() {}

    public var attachedApp: AppIdentity? { app }

    public func attach(_ app: AppIdentity) throws {
        AXReader.configure()                      // cap AX messaging at 0.25 s before the first call (spec §5.1)
        detach()
        var created: AXObserver?
        let error = AXObserverCreate(app.pid, MenuObserver.callback, &created)
        guard error == .success, let observer = created else { throw MenuObserverError.createFailed(error.rawValue) }

        let element = AXUIElementCreateApplication(app.pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            let result = AXObserverAddNotification(observer, element, name as CFString, refcon)
            if result != .success && result != .notificationAlreadyRegistered {
                throw MenuObserverError.registrationFailed(notification: name, code: result.rawValue)
            }
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = observer
        self.appElement = element
        self.app = app
    }

    public func detach() {
        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            if let appElement {
                for name in Self.notifications {
                    AXObserverRemoveNotification(observer, appElement, name as CFString)
                }
            }
        }
        observer = nil
        appElement = nil
        app = nil
    }

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let me = Unmanaged<MenuObserver>.fromOpaque(refcon).takeUnretainedValue()
        let name = notification as String
        nonisolated(unsafe) let element = element   // AXUIElement is not Sendable; the observer fires on the main run loop
        MainActor.assumeIsolated {
            me.handle(name, element: element)
        }
    }

    private func handle(_ name: String, element: AXUIElement) {
        switch name {
        case kAXMenuOpenedNotification:
            onEvent?(.menuOpened)
        case kAXMenuClosedNotification:
            onEvent?(.menuClosed)
        case kAXMenuItemSelectedNotification:
            guard let app, let record = MenuItemResolver.record(for: element, bundleID: app.bundleID) else { return }
            onEvent?(.itemSelected(record))
        default:
            break
        }
    }
}

/// Turns the AXMenuItem from a selection notification into a `MenuItemRecord`
/// by reading its attributes and walking up to the menu bar for the path.
enum MenuItemResolver {
    private static let attributes: [String] = [
        kAXRoleAttribute, kAXTitleAttribute, kAXEnabledAttribute,
        kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdGlyphAttribute,
    ]

    static func record(for element: AXUIElement, bundleID: String) -> MenuItemRecord? {
        let values = AXReader.multiple(element, attributes)
        guard (values[kAXRoleAttribute] as? String) == "AXMenuItem" else { return nil }
        let title = (values[kAXTitleAttribute] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var path = [title]
        var current = element
        var depth = 0
        while depth < 32, let parent = AXReader.element(current, kAXParentAttribute) {
            depth += 1
            let role = AXReader.string(parent, kAXRoleAttribute) ?? ""
            if role == "AXMenuBarItem" {
                let barTitle = AXReader.string(parent, kAXTitleAttribute) ?? ""
                path.insert(barTitle.isEmpty || barTitle == "Apple" ? "Apple" : barTitle, at: 0)
                break
            }
            if role == "AXMenuItem" {
                let parentTitle = (AXReader.string(parent, kAXTitleAttribute) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if !parentTitle.isEmpty { path.insert(parentTitle, at: 0) }
            }
            if role == "AXMenuBar" || role == "AXApplication" { break }
            current = parent
        }

        let node = AXMenuNode(
            role: "AXMenuItem",
            title: title,
            isEnabled: (values[kAXEnabledAttribute] as? NSNumber)?.boolValue ?? true,
            cmdChar: values[kAXMenuItemCmdCharAttribute] as? String,
            cmdModifiers: (values[kAXMenuItemCmdModifiersAttribute] as? NSNumber)?.intValue,
            cmdVirtualKey: (values[kAXMenuItemCmdVirtualKeyAttribute] as? NSNumber)?.intValue,
            cmdGlyph: (values[kAXMenuItemCmdGlyphAttribute] as? NSNumber)?.intValue
        )
        return MenuTreeBuilder.record(for: node, path: path, bundleID: bundleID)
    }
}
