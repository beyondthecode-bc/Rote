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

/// The Accessibility calls the observer makes for one app. Production wraps an `AXObserver`;
/// tests script busy and failing apps (spec §11).
protocol MenuNotificationConnection: AnyObject {
    func add(_ notification: String) -> AXError
    func remove(_ notification: String)
    /// Resolves the element a selection notification carries.
    func record(for element: AXUIElement, bundleID: String) -> MenuItemRecord?
    /// Stops delivery by taking the observer off the main run loop.
    func close()
}

/// Listens to one app's menu notifications (spec §4.3). Attach on activation, detach on deactivation.
@MainActor
public final class MenuObserver {
    public var onEvent: ((MenuObserverEvent) -> Void)?

    private let connect: @MainActor (AppIdentity, MenuObserver) throws -> any MenuNotificationConnection
    private let retryDelays: [Duration]
    private var connection: (any MenuNotificationConnection)?
    private var registered: [String] = []
    private var app: AppIdentity?
    private(set) var retryTask: Task<Void, Never>?

    /// Registration order. A busy app can leave only the first few registered for a while, and the
    /// engine classifies a selection by the open/close count (spec §4.3): an open seen without its
    /// close would make later shortcut selections look like menu uses, a selection seen without
    /// opens and closes would make mouse picks look like shortcut uses.
    static let notifications: [String] = [
        kAXMenuClosedNotification, kAXMenuOpenedNotification, kAXMenuItemSelectedNotification,
    ]

    /// Waits before each retry when the app was too busy to answer (spec §11). After the last one,
    /// what is still unregistered stays so until the app's next activation.
    static let defaultRetryDelays: [Duration] = [.milliseconds(500), .seconds(1), .seconds(2), .seconds(4)]

    public convenience init() {
        self.init(retryDelays: MenuObserver.defaultRetryDelays) { app, observer in
            try AXMenuNotificationConnection(pid: app.pid, callback: MenuObserver.callback, refcon: Unmanaged.passUnretained(observer).toOpaque())
        }
    }

    init(retryDelays: [Duration], connect: @escaping @MainActor (AppIdentity, MenuObserver) throws -> any MenuNotificationConnection) {
        self.retryDelays = retryDelays
        self.connect = connect
    }

    public var attachedApp: AppIdentity? { app }

    /// Throws when the app cannot be observed at all. An app too busy to answer (`.cannotComplete`)
    /// is not an error: what registered is kept and the rest is retried while the app stays attached.
    public func attach(_ app: AppIdentity) throws {
        AXReader.configure()                      // cap AX messaging at 0.25 s before the first call (spec §5.1)
        detach()
        connection = try connect(app, self)
        self.app = app
        do {
            try register(Self.notifications, retry: 0)
        } catch {
            detach()
            throw error
        }
    }

    public func detach() {
        retryTask?.cancel()
        retryTask = nil
        if let connection {
            connection.close()
            for name in registered { connection.remove(name) }
        }
        connection = nil
        registered = []
        app = nil
    }

    /// Registers `names` in order. After a `.cannotComplete` the busy app is not messaged again on
    /// this try, so one try blocks the main actor for one messaging timeout at most.
    private func register(_ names: [String], retry: Int) throws {
        guard let connection else { return }
        for (index, name) in names.enumerated() {
            let result = connection.add(name)
            switch result {
            case .success, .notificationAlreadyRegistered:
                registered.append(name)
            case .cannotComplete:
                scheduleRetry(Array(names[index...]), retry: retry)
                return
            default:
                throw MenuObserverError.registrationFailed(notification: name, code: result.rawValue)
            }
        }
    }

    private func scheduleRetry(_ names: [String], retry: Int) {
        guard retry < retryDelays.count else { return }
        let delay = retryDelays[retry]
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }   // detach and attach cancel it first
            self.retryTask = nil
            do {
                try self.register(names, retry: retry + 1)
            } catch {
                self.detach()
            }
        }
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

    func handle(_ name: String, element: AXUIElement) {
        switch name {
        case kAXMenuOpenedNotification:
            onEvent?(.menuOpened)
        case kAXMenuClosedNotification:
            onEvent?(.menuClosed)
        case kAXMenuItemSelectedNotification:
            guard let app, let record = connection?.record(for: element, bundleID: app.bundleID) else { return }
            onEvent?(.itemSelected(record))
        default:
            break
        }
    }
}

/// `MenuNotificationConnection` over a live `AXObserver` whose callbacks arrive on the main run loop.
final class AXMenuNotificationConnection: MenuNotificationConnection {
    private let observer: AXObserver
    private let application: AXUIElement
    private let refcon: UnsafeMutableRawPointer

    init(pid: pid_t, callback: AXObserverCallback, refcon: UnsafeMutableRawPointer) throws {
        var created: AXObserver?
        let error = AXObserverCreate(pid, callback, &created)
        guard error == .success, let observer = created else { throw MenuObserverError.createFailed(error.rawValue) }
        self.observer = observer
        self.application = AXUIElementCreateApplication(pid)
        self.refcon = refcon
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    func add(_ notification: String) -> AXError {
        AXObserverAddNotification(observer, application, notification as CFString, refcon)
    }

    func remove(_ notification: String) {
        AXObserverRemoveNotification(observer, application, notification as CFString)
    }

    func record(for element: AXUIElement, bundleID: String) -> MenuItemRecord? {
        MenuItemResolver.record(for: element, source: AXMenuItemSource(application: application), bundleID: bundleID)
    }

    func close() {
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }
}

/// The reads `MenuItemResolver` makes. Production reads a live app; tests replay a recorded hierarchy.
protocol MenuItemSource {
    associatedtype Element
    func attributes(of element: Element, _ names: [String]) -> [String: AnyObject]
    func parent(of element: Element) -> Element?
    /// True for the app's main menu bar (`kAXMenuBarAttribute`), the one `MenuScanner` walks.
    func isMainMenuBar(_ element: Element) -> Bool
}

struct AXMenuItemSource: MenuItemSource {
    let application: AXUIElement

    func attributes(of element: AXUIElement, _ names: [String]) -> [String: AnyObject] {
        AXReader.multiple(element, names)
    }

    func parent(of element: AXUIElement) -> AXUIElement? {
        AXReader.element(element, kAXParentAttribute)
    }

    func isMainMenuBar(_ element: AXUIElement) -> Bool {
        AXReader.element(application, kAXMenuBarAttribute).map { CFEqual($0, element) } ?? false
    }
}

/// Turns the AXMenuItem from a selection notification into a `MenuItemRecord`
/// by reading its attributes and walking up to the menu bar for the path.
/// Items outside the app's main menu bar resolve to nil.
enum MenuItemResolver {
    private static let attributes: [String] = [
        kAXRoleAttribute, kAXTitleAttribute, kAXEnabledAttribute,
        kAXMenuItemCmdCharAttribute, kAXMenuItemCmdModifiersAttribute,
        kAXMenuItemCmdVirtualKeyAttribute, kAXMenuItemCmdGlyphAttribute,
    ]

    static func record<Source: MenuItemSource>(for element: Source.Element, source: Source, bundleID: String) -> MenuItemRecord? {
        let values = source.attributes(of: element, attributes)
        guard (values[kAXRoleAttribute] as? String) == "AXMenuItem" else { return nil }
        let title = (values[kAXTitleAttribute] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var path = [title]
        var current = element
        var depth = 0
        var reachedMenuBar = false
        while depth < 32, let parent = source.parent(of: current) {
            depth += 1
            let parentValues = source.attributes(of: parent, [kAXRoleAttribute, kAXTitleAttribute])
            let role = parentValues[kAXRoleAttribute] as? String ?? ""
            let parentTitle = parentValues[kAXTitleAttribute] as? String ?? ""
            if role == "AXMenuBarItem" {
                // A status-item menu also ends in an AXMenuBarItem, under the app's extras bar.
                guard let bar = source.parent(of: parent), source.isMainMenuBar(bar) else { return nil }
                path.insert(parentTitle.isEmpty || parentTitle == "Apple" ? "Apple" : parentTitle, at: 0)
                reachedMenuBar = true
                break
            }
            if role == "AXMenuItem" {
                let trimmed = parentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { path.insert(trimmed, at: 0) }
            }
            if role == "AXMenuBar" || role == "AXApplication" { break }
            current = parent
        }
        // Context, pop-up and status-item menus are not coached (spec §2), and the scan never holds them.
        guard reachedMenuBar else { return nil }

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
