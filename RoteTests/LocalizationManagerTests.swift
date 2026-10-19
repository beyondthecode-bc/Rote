import XCTest
@testable import Rote

/// String tables from a temporary bundle and a throwaway defaults suite; the shipped tables from the app bundle.
@MainActor
final class LocalizationManagerTests: XCTestCase {
    private static let english = """
    <?xml version="1.0" encoding="UTF-8"?>
    <strings>
      <string key="greeting">Hello, %1</string>
      <string key="pair">%1 and %2</string>
      <string key="englishOnly">Only in English</string>
      <string key="blankInFrench">Not blank</string>
      <string key="edge">%0 %3 %1 % %x 100% %١</string>
    </strings>
    """

    private static let french = """
    <?xml version="1.0" encoding="UTF-8"?>
    <strings>
      <string key="greeting">Bonjour, %1</string>
      <string key="pair">%2 et %1</string>
      <string key="blankInFrench">   </string>
    </strings>
    """

    private func makeManager(language: String?) throws -> (LocalizationManager, TestDefaults) {
        let directory = try TemporaryDirectory()
        let testDefaults = TestDefaults()
        addTeardownBlock {
            directory.remove()
            testDefaults.remove()
        }
        let languages = directory.url.appendingPathComponent("languages", isDirectory: true)
        try FileManager.default.createDirectory(at: languages, withIntermediateDirectories: true)
        try Data(Self.english.utf8).write(to: languages.appendingPathComponent("English.xml"))
        try Data(Self.french.utf8).write(to: languages.appendingPathComponent("French.xml"))
        if let language { testDefaults.defaults.set(language, forKey: "rote.language") }
        let bundle = try XCTUnwrap(Bundle(url: directory.url))
        return (LocalizationManager(defaults: testDefaults.defaults, bundle: bundle), testDefaults)
    }

    func testTheChosenLanguagesStringIsUsed() throws {
        let (manager, _) = try makeManager(language: "fr")
        XCTAssertEqual(manager.languageCode, "fr")
        XCTAssertEqual(manager.string(for: "greeting"), "Bonjour, %1")
        XCTAssertEqual(manager.string(for: "greeting", ["Vlad"]), "Bonjour, Vlad")
    }

    func testAKeyTheTranslationLacksFallsBackToEnglish() throws {
        let (manager, _) = try makeManager(language: "fr")
        XCTAssertEqual(manager.string(for: "englishOnly"), "Only in English")
    }

    func testABlankTranslationFallsBackToEnglish() throws {
        let (manager, _) = try makeManager(language: "fr")
        XCTAssertEqual(manager.string(for: "blankInFrench"), "Not blank")
    }

    func testAnUnknownKeyShowsTheKey() throws {
        let (manager, _) = try makeManager(language: "fr")
        XCTAssertEqual(manager.string(for: "missing.key"), "missing.key")
        XCTAssertEqual(manager.string(for: "missing.key", ["x"]), "missing.key")
    }

    func testALanguageWithoutATableUsesEnglish() throws {
        let (manager, _) = try makeManager(language: "de")      // no German.xml in this bundle
        XCTAssertEqual(manager.string(for: "greeting"), "Hello, %1")
    }

    func testPlaceholdersAreFilledInOnePassInTheTranslationsOrder() throws {
        let (manager, _) = try makeManager(language: "fr")
        XCTAssertEqual(manager.string(for: "pair", ["A", "B"]), "B et A")
        XCTAssertEqual(manager.string(for: "pair", ["%2", "B"]), "B et %2", "an inserted %2 is never substituted again")
    }

    func testPlaceholdersOutOfRangeOrMalformedStayAsWritten() throws {
        let (manager, _) = try makeManager(language: "en")
        XCTAssertEqual(manager.string(for: "edge", ["a", "b"]), "%0 %3 a % %x 100% %١")
        XCTAssertEqual(manager.string(for: "pair", ["only"]), "only and %2")
        XCTAssertEqual(manager.string(for: "pair", []), "%1 and %2")
    }

    func testChangingTheLanguageSavesItAndReloads() throws {
        let (manager, store) = try makeManager(language: "fr")
        manager.languageCode = "en"
        XCTAssertEqual(manager.string(for: "greeting"), "Hello, %1")
        XCTAssertEqual(store.defaults.string(forKey: "rote.language"), "en")

        manager.languageCode = "fr"
        XCTAssertEqual(manager.string(for: "pair", ["A", "B"]), "B et A")
        XCTAssertEqual(store.defaults.string(forKey: "rote.language"), "fr")
    }

    func testWithNoSavedChoiceTheLanguageFollowsTheSystem() throws {
        let (manager, _) = try makeManager(language: nil)
        XCTAssertEqual(manager.languageCode, "system")
        XCTAssertEqual(manager.string(for: "englishOnly"), "Only in English")
    }

    func testTheSystemLanguageMatchesASupportedCodeOrEnglish() {
        XCTAssertEqual(LocalizationManager.systemCode(preferred: ["fr-CA"]), "fr")
        XCTAssertEqual(LocalizationManager.systemCode(preferred: ["ja-JP"]), "ja")
        XCTAssertEqual(LocalizationManager.systemCode(preferred: ["pt-BR"]), "pt-BR")
        XCTAssertEqual(LocalizationManager.systemCode(preferred: ["xx", "de-AT"]), "de")
        XCTAssertNotEqual(LocalizationManager.systemCode(preferred: ["zh-Hant-TW"]), "zh-Hans")
        XCTAssertNotEqual(LocalizationManager.systemCode(preferred: ["kok"]), "ko")
    }

    func testEveryShippedLanguageLoadsFromTheAppBundle() throws {
        let englishDefaults = TestDefaults()
        defer { englishDefaults.remove() }
        englishDefaults.defaults.set("en", forKey: "rote.language")
        let english = LocalizationManager(defaults: englishDefaults.defaults, bundle: .main).strings

        for code in LocalizationManager.supportedCodes {
            let testDefaults = TestDefaults()
            defer { testDefaults.remove() }
            testDefaults.defaults.set(code, forKey: "rote.language")

            let manager = LocalizationManager(defaults: testDefaults.defaults, bundle: .main)

            XCTAssertFalse(manager.strings.isEmpty, code)
            XCTAssertNotEqual(manager.string(for: "nudge.snooze"), "nudge.snooze", code)
            let announcement = manager.string(for: "nudge.announcement", ["Save", "Command S"])
            XCTAssertTrue(announcement.contains("Save") && announcement.contains("Command S"), "\(code): \(announcement)")
            if code != "en" { XCTAssertNotEqual(manager.strings, english, "\(code) loads its own table") }
        }
    }
}
