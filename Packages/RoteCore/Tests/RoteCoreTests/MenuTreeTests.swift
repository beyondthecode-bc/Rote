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

    private func menu(_ title: String, _ items: [MenuItemRecord] = [], isComplete: Bool = true) -> MenuTree.Menu {
        MenuTree.Menu(title: title, isAppleMenu: title == "Apple", items: items, isComplete: isComplete)
    }

    private func scan(_ menus: [MenuTree.Menu], isPartial: Bool, at seconds: TimeInterval = 100, bundleID: String = "com.apple.Safari") -> MenuTree {
        MenuTree(bundleID: bundleID, appName: "Safari", menus: menus, scannedAt: Date(timeIntervalSinceReferenceDate: seconds), isPartial: isPartial)
    }

    func testCompleteOrFirstScanStandsAsIs() {
        let complete = scan([menu("Apple"), menu("Safari", [about])], isPartial: false)
        XCTAssertEqual(complete.merged(over: tree), complete)
        let partial = scan([menu("Apple")], isPartial: true)
        XCTAssertEqual(partial.merged(over: nil), partial)
        XCTAssertEqual(partial.merged(over: scan([menu("Other")], isPartial: false, bundleID: "com.example.other")), partial)
    }

    /// A busy app answers a rescan with a partial tree (spec §5.1, §11). The menus it read in
    /// full replace their cached copies; every other cached menu stays, and so does `isPartial`.
    func testPartialScanKeepsCachedMenusItDidNotFinish() {
        let newAbout = MenuItemRecord(bundleID: "com.apple.Safari", path: ["Apple", "About This Mac"], shortcut: nil)
        let partial = scan([menu("Apple", [newAbout]), menu("Safari", [], isComplete: false)], isPartial: true)
        let merged = partial.merged(over: tree)
        XCTAssertEqual(merged.menus.map(\.title), ["Apple", "Safari", "View"])
        XCTAssertEqual(merged.menus[0].items, [newAbout], "a menu read in full is fresh")
        XCTAssertEqual(merged.menus[1].items, [about], "a menu cut short keeps its cached items")
        XCTAssertEqual(merged.item(for: Shortcut(modifiers: [.command], key: .character("R"))), reload)
        XCTAssertTrue(merged.isPartial, "still rescanned on the next activation")
        XCTAssertEqual(merged.scannedAt, partial.scannedAt)
    }

    func testEmptyPartialScanNeverEmptiesTheCache() {
        let merged = scan([], isPartial: true).merged(over: tree)
        XCTAssertEqual(merged.menus, tree.menus)
        XCTAssertTrue(merged.isPartial)
    }

    func testMenuCutShortIsKeptWhenTheCacheLacksIt() {
        let cached = scan([menu("Apple")], isPartial: true, at: 0)
        let partial = scan([menu("Apple"), menu("Safari", [about], isComplete: false)], isPartial: true)
        XCTAssertEqual(partial.merged(over: cached).menus.map(\.title), ["Apple", "Safari"])
    }

    func testTreeRoundTripsThroughJSON() throws {
        let data = try JSONEncoder().encode(tree)
        XCTAssertEqual(try JSONDecoder().decode(MenuTree.self, from: data), tree)
    }
}
