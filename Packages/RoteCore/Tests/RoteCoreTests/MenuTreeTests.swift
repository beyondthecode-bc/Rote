import XCTest
@testable import RoteCore

final class MenuTreeTests: XCTestCase {
    private let reload = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Reload Page"], shortcut: Shortcut(modifiers: [.command], key: .character("R")))
    private let readerDisabled = MenuItemRecord(bundleID: "com.apple.Safari", path: ["View", "Show Reader"], shortcut: Shortcut(modifiers: [.shift, .command], key: .character("R")), isEnabled: false)
    private let about = MenuItemRecord(bundleID: "com.apple.Safari", path: ["Safari", "About Safari"], shortcut: nil)

    private var tree: MenuTree {
        MenuTree(
            bundleID: "com.apple.Safari",
            appName: "Safari",
            menus: [
                MenuTree.Menu(title: "Apple", isAppleMenu: true, items: []),
                MenuTree.Menu(title: "Safari", isAppleMenu: false, items: [about]),
                MenuTree.Menu(title: "View", isAppleMenu: false, items: [reload, readerDisabled]),
            ],
            scannedAt: Date(timeIntervalSinceReferenceDate: 0),
            isPartial: false
        )
    }

    func testShortcutCountIgnoresItemsWithoutShortcut() {
        XCTAssertEqual(tree.shortcutCount, 2)
    }

    func testItemForShortcutReturnsEnabledMatch() {
        XCTAssertEqual(tree.item(for: Shortcut(modifiers: [.command], key: .character("R"))), reload)
        XCTAssertNil(tree.item(for: Shortcut(modifiers: [.shift, .command], key: .character("R"))), "disabled items do not match")
        XCTAssertNil(tree.item(for: Shortcut(modifiers: [.command], key: .character("Z"))))
    }

    func testContainsIdentity() {
        XCTAssertTrue(tree.contains(identity: reload.identity))
        XCTAssertFalse(tree.contains(identity: "com.apple.Safari|View›Nothing"))
    }

    func testTreeRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(tree)
        XCTAssertEqual(try JSONDecoder().decode(MenuTree.self, from: data), tree)
    }
}
