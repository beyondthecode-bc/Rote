import XCTest
@testable import RoteAX

final class MenuTitleSanitizerTests: XCTestCase {
    private func sanitize(_ raw: String) -> String { MenuTitleSanitizer.sanitize(raw) }

    func testOrdinaryTitlesPassUnchanged() {
        for title in ["Eject “Backup”", "Move to “Inbox” Again", "Find…", "Zoom In", "Émoji 🎉", "ファイルを開く", "Hide Safari"] {
            XCTAssertEqual(sanitize(title), title)
        }
    }

    /// A right-to-left override makes "Eject Backup" read as "pukcaB tcejE" and can hide what a
    /// title says; the bell, isolates, soft hyphens and a byte-order mark are never part of a name.
    func testControlAndFormatCharactersAreStripped() {
        XCTAssertEqual(sanitize("\u{202E}Eject “Backup”\u{07}"), "Eject “Backup”")
        XCTAssertEqual(sanitize("\u{2066}Open\u{2069} \u{202A}Recent\u{202C}"), "Open Recent")
        XCTAssertEqual(sanitize("co\u{00AD}operate\u{FEFF}"), "cooperate")
        XCTAssertEqual(sanitize("\u{200E}Left\u{200F}\u{061C}"), "Left")
        XCTAssertEqual(sanitize("\u{1B}[31mRed\u{1B}[0m"), "[31mRed[0m")
    }

    func testControlWhitespaceBecomesASpaceAndEndsAreTrimmed() {
        XCTAssertEqual(sanitize("  Open\nRecent\t "), "Open Recent")
        XCTAssertEqual(sanitize("\u{07}\u{00}"), "")
    }

    /// Joiners stay: without them a family emoji falls apart and Persian letters join wrongly.
    func testJoinersAreKept() {
        XCTAssertEqual(sanitize("👨‍👩‍👧 Family"), "👨‍👩‍👧 Family")
        XCTAssertEqual(sanitize("می‌خواهم"), "می‌خواهم")
    }

    func testLongTitlesAreCappedOnACharacterBoundary() {
        let long = sanitize(String(repeating: "x", count: 1_000))
        XCTAssertEqual(long.unicodeScalars.count, MenuTitleSanitizer.maxScalars)
        XCTAssertEqual(sanitize(String(repeating: "x", count: MenuTitleSanitizer.maxScalars)).count, MenuTitleSanitizer.maxScalars)
        // e + combining acute is one character of two scalars; it does not fit after 255 x's.
        let mark = sanitize(String(repeating: "x", count: MenuTitleSanitizer.maxScalars - 1) + "e\u{0301}" + "y")
        XCTAssertEqual(mark.unicodeScalars.count, MenuTitleSanitizer.maxScalars - 1)
        XCTAssertFalse(mark.contains("e"))
        let flags = sanitize(String(repeating: "🇫🇷", count: 300))
        XCTAssertEqual(flags.count, MenuTitleSanitizer.maxScalars / 2, "a flag is two scalars and is never split")
        XCTAssertEqual(sanitize(String(repeating: "x", count: 255) + " " + String(repeating: "y", count: 10)), String(repeating: "x", count: 255), "a space left at the cut is trimmed")
    }
}
