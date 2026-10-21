import XCTest
import RoteCore
@testable import RoteAX

final class MenuTreeBuilderTests: XCTestCase {
    private func loadFixture() throws -> MenuSnapshot {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "safari-mini", withExtension: "json", subdirectory: "Fixtures"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MenuSnapshot.self, from: Data(contentsOf: url))
    }

    private func tree() throws -> MenuTree { MenuTreeBuilder.build(try loadFixture()) }

    func testMenusKeepMenuBarOrderAndFlagApple() throws {
        let t = try tree()
        XCTAssertEqual(t.menus.map(\.title), ["Apple", "Safari", "File", "Edit", "View", "Window"])
        XCTAssertTrue(t.menus[0].isAppleMenu)
        XCTAssertFalse(t.menus[1].isAppleMenu)
        XCTAssertEqual(t.appName, "Safari")
        XCTAssertEqual(t.bundleID, "com.apple.Safari")
        XCTAssertEqual(t.scannedAt, ISO8601DateFormatter().date(from: "2026-10-18T10:00:00Z"))
        XCTAssertFalse(t.isPartial)
        XCTAssertTrue(t.menus.allSatisfy(\.isComplete))
    }

    func testSeparatorsAreSkipped() throws {
        let safari = try tree().menus[1]
        XCTAssertEqual(safari.items.map(\.title), ["About Safari", "Settings…", "Hide Safari"])
    }

    /// The fixture holds key equivalents as Accessibility reports them: letters in uppercase,
    /// Shift only in mask bit 1. Finder's ⌘N / ⇧⌘N pair arrives as ("N", 0) and ("N", 1).
    func testShortcutsDecodeWithModifiers() throws {
        let t = try tree()
        let file = t.menus[2]
        let commandN = Shortcut(modifiers: [.command], key: .character("N"))
        let shiftCommandN = Shortcut(modifiers: [.shift, .command], key: .character("N"))
        XCTAssertEqual(file.items[0].shortcut, commandN)
        XCTAssertEqual(file.items[1].shortcut, shiftCommandN)
        XCTAssertEqual(t.item(for: commandN)?.title, "New Window")
        XCTAssertEqual(t.item(for: shiftCommandN)?.title, "New Private Window")
        XCTAssertEqual(t.menus[5].items[0].shortcut, Shortcut(modifiers: [.command], key: .character("M")))
        let view = t.menus[4]
        XCTAssertEqual(view.items[0].shortcut, Shortcut(modifiers: [.command], key: .character("R")))
        XCTAssertEqual(view.items[1].shortcut, Shortcut(modifiers: [.shift, .command], key: .character("R")))
        XCTAssertEqual(view.items[2].shortcut, Shortcut(modifiers: [.control, .command], key: .character("F")))
        XCTAssertEqual(t.menus[0].items[1].shortcut, Shortcut(modifiers: [.control, .command], key: .character("Q")))
    }

    func testDisabledStateIsKept() throws {
        let file = try tree().menus[2]
        XCTAssertFalse(file.items[2].isEnabled)
        XCTAssertEqual(file.items[2].title, "Close Tab")
    }

    func testSubmenusAreFlattenedWithParentPath() throws {
        let edit = try tree().menus[3]
        let findNext = try XCTUnwrap(edit.items.first { $0.title == "Find Next" })
        XCTAssertEqual(findNext.path, ["Edit", "Find", "Find Next"])
        XCTAssertEqual(findNext.parentPath, ["Find"])
        XCTAssertEqual(findNext.bundleID, "com.apple.Safari")
        XCTAssertEqual(findNext.identity, "com.apple.Safari|Edit›Find›Find Next")
        XCTAssertNil(edit.items.first { $0.title == "Find" }, "a parent item with a submenu is not itself listed")
        let encodingDefault = try XCTUnwrap(try tree().menus[4].items.first { $0.title == "Default" })
        XCTAssertEqual(encodingDefault.path, ["View", "Text Encoding", "Default"])
        XCTAssertNil(encodingDefault.shortcut)
    }

    func testUnrenderableAndGlyphItems() throws {
        let edit = try tree().menus[3]
        let strange = try XCTUnwrap(edit.items.first { $0.title == "Strange Item" })
        XCTAssertNil(strange.shortcut)
        XCTAssertTrue(strange.hasUnrenderableShortcut)
        let delete = try XCTUnwrap(edit.items.first { $0.title == "Delete" })
        XCTAssertEqual(delete.shortcut, Shortcut(modifiers: [.command], key: .special(.delete)))
    }

    /// fn/Globe items (mask bit 16) and a "ß" that Accessibility uppercased to "SS" render as "?"
    /// and are never coached, instead of being taught as E, ⌃F, ⌃← or ⌘S.
    func testFunctionAndMultiCharacterItemsAreUnrenderable() throws {
        let t = try tree()
        for (menu, title) in [(3, "Emoji & Symbols"), (3, "Sharp S Item"), (5, "Fill"), (5, "Left")] {
            let item = try XCTUnwrap(t.menus[menu].items.first { $0.title == title }, title)
            XCTAssertNil(item.shortcut, title)
            XCTAssertTrue(item.hasUnrenderableShortcut, title)
            XCTAssertFalse(item.isCoachable, title)
        }
        XCTAssertEqual(t.menus[5].items.map(\.path), [["Window", "Minimize"], ["Window", "Fill"], ["Window", "Move & Resize", "Left"]])
    }

    func testShortcutCount() throws {
        // Disabled items keep their shortcut; the unrenderable ones and the submenu "Default" have none.
        XCTAssertEqual(try tree().shortcutCount, 15)
    }

    // MARK: Hostile snapshots (audit M3)

    func testDeepSubmenusStopAtTheDepthCap() {
        let tree = MenuTreeBuilder.build(MenuScannerTests.nested(levels: 40))
        XCTAssertTrue(tree.isPartial)
        XCTAssertEqual(tree.menus.count, 1)
        XCTAssertFalse(tree.menus[0].isComplete)
        XCTAssertTrue(tree.menus[0].items.isEmpty, "the only item lies past the cap")
        let shallow = MenuTreeBuilder.build(MenuScannerTests.nested(levels: 4))
        XCTAssertFalse(shallow.isPartial)
        XCTAssertEqual(shallow.menus[0].items.map(\.path), [["Deep", "Level 1", "Level 2", "Level 3", "Level 4", "Deepest"]])
    }

    func testSubmenusAtTheCapAreCollected() {
        let tree = MenuTreeBuilder.build(MenuScannerTests.nested(levels: MenuTreeBuilder.maxDepth - 2))
        XCTAssertFalse(tree.isPartial)
        XCTAssertEqual(tree.menus[0].items.first?.path.count, MenuTreeBuilder.maxDepth)
        let over = MenuTreeBuilder.build(MenuScannerTests.nested(levels: MenuTreeBuilder.maxDepth - 1))
        XCTAssertTrue(over.isPartial)
        XCTAssertTrue(over.menus[0].items.isEmpty)
    }

    func testNodeCapMarksTheTreePartial() {
        let tree = MenuTreeBuilder.build(MenuScannerTests.flat(count: MenuTreeBuilder.maxNodes + 1_000))
        XCTAssertTrue(tree.isPartial)
        XCTAssertFalse(tree.menus[0].isComplete)
        XCTAssertEqual(tree.menus[0].items.count, MenuTreeBuilder.maxNodes)
        let wide = MenuTreeBuilder.build(MenuScannerTests.flat(count: MenuTreeBuilder.maxNodes))
        XCTAssertFalse(wide.isPartial)
        XCTAssertEqual(wide.menus[0].items.count, MenuTreeBuilder.maxNodes)
    }

    func testPartialFlagPropagates() throws {
        var snapshot = try loadFixture()
        snapshot.isPartial = true
        XCTAssertTrue(MenuTreeBuilder.build(snapshot).isPartial)
    }

    /// Only bar items before `completeBarItemCount` were read in full; a later menu may be cut short.
    func testMenusPastTheCompleteCountAreIncomplete() throws {
        var snapshot = try loadFixture()
        snapshot.isPartial = true
        snapshot.completeBarItemCount = 4
        XCTAssertEqual(MenuTreeBuilder.build(snapshot).menus.map(\.isComplete), [true, true, true, true, false, false])
    }
}
