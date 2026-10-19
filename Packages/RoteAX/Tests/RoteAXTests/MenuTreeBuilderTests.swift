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
        XCTAssertEqual(t.menus.map(\.title), ["Apple", "Safari", "File", "Edit", "View"])
        XCTAssertTrue(t.menus[0].isAppleMenu)
        XCTAssertFalse(t.menus[1].isAppleMenu)
        XCTAssertEqual(t.appName, "Safari")
        XCTAssertFalse(t.isPartial)
    }

    func testSeparatorsAreSkipped() throws {
        let safari = try tree().menus[1]
        XCTAssertEqual(safari.items.map(\.title), ["About Safari", "Settings…", "Hide Safari"])
    }

    func testShortcutsDecodeWithModifiers() throws {
        let t = try tree()
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

    func testShortcutCount() throws {
        // Disabled items keep their shortcut; the unrenderable one and the submenu "Default" have none.
        XCTAssertEqual(try tree().shortcutCount, 14)
    }

    func testPartialFlagPropagates() throws {
        var snapshot = try loadFixture()
        snapshot.isPartial = true
        XCTAssertTrue(MenuTreeBuilder.build(snapshot).isPartial)
    }
}
