import XCTest
@testable import Rote
import RoteCore

/// Plural forms, spoken shortcuts, number formats and update errors, in the shipped tables of
/// every language and in small tables written to a temporary bundle.
@MainActor
final class LocalizedFormsTests: XCTestCase {
    /// The shipped table for `code`, chosen through a throwaway defaults suite.
    private func shipped(_ code: String) -> LocalizationManager {
        let testDefaults = TestDefaults()
        addTeardownBlock { testDefaults.remove() }
        testDefaults.defaults.set(code, forKey: "rote.language")
        return LocalizationManager(defaults: testDefaults.defaults, bundle: .main)
    }

    /// A manager over `tables` (file name → XML body) in a temporary bundle.
    private func custom(_ tables: [String: String], language: String) throws -> LocalizationManager {
        let directory = try TemporaryDirectory()
        let testDefaults = TestDefaults()
        addTeardownBlock {
            directory.remove()
            testDefaults.remove()
        }
        let languages = directory.url.appendingPathComponent("languages", isDirectory: true)
        try FileManager.default.createDirectory(at: languages, withIntermediateDirectories: true)
        for (name, body) in tables {
            let xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<strings>\n\(body)\n</strings>\n"
            try Data(xml.utf8).write(to: languages.appendingPathComponent("\(name).xml"))
        }
        testDefaults.defaults.set(language, forKey: "rote.language")
        let bundle = try XCTUnwrap(Bundle(url: directory.url))
        return LocalizationManager(defaults: testDefaults.defaults, bundle: bundle, preferredLanguages: { ["en-US"] })
    }

    // MARK: Plurals

    func testEachLanguagePicksTheOneFormByItsIntegerRule() {
        let one: [String: Set<Int>] = [
            "en": [1], "de": [1], "es": [1],
            "fr": [0, 1], "pt-BR": [0, 1],
            "ja": [], "ko": [], "zh-Hans": [],
        ]
        XCTAssertEqual(Set(one.keys), Set(LocalizationManager.supportedCodes))
        for code in LocalizationManager.supportedCodes {
            for count in [0, 1, 2, 3, 11, 21, 101, 1_000] {
                let expected: LocalizationManager.PluralCategory = one[code]!.contains(count) ? .one : .other
                XCTAssertEqual(LocalizationManager.pluralCategory(for: count, language: code), expected, "\(code) \(count)")
            }
        }
    }

    func testOneHourReadsAsOneHourInEveryLanguage() {
        let expected: [String: (one: String, two: String)] = [
            "en": ("At least 1 hour between nudges for the same item", "At least 2 hours between nudges for the same item"),
            "fr": ("Au moins 1 heure entre deux suggestions pour un même élément", "Au moins 2 heures entre deux suggestions pour un même élément"),
            "de": ("Mindestens 1 Stunde zwischen Hinweisen zum selben Objekt", "Mindestens 2 Stunden zwischen Hinweisen zum selben Objekt"),
            "es": ("Al menos 1 hora entre sugerencias del mismo ítem", "Al menos 2 horas entre sugerencias del mismo ítem"),
            "pt-BR": ("Pelo menos 1 hora entre dicas do mesmo item", "Pelo menos 2 horas entre dicas do mesmo item"),
            "ja": ("同じ項目のヒントは1時間以上空ける", "同じ項目のヒントは2時間以上空ける"),
            "ko": ("같은 항목은 최소 1시간 간격으로 코칭", "같은 항목은 최소 2시간 간격으로 코칭"),
            "zh-Hans": ("同一项目的提示至少间隔 1 小时", "同一项目的提示至少间隔 2 小时"),
        ]
        XCTAssertEqual(Set(expected.keys), Set(LocalizationManager.supportedCodes))
        for (code, forms) in expected {
            let manager = shipped(code)
            XCTAssertEqual(manager.string(for: "settings.itemSpacing", count: 1, ["1"]), forms.one, code)
            XCTAssertEqual(manager.string(for: "settings.itemSpacing", count: 2, ["2"]), forms.two, code)
        }
    }

    func testCountPhrasesTakeTheFormOfTheirCount() {
        let english = shipped("en")
        XCTAssertEqual(english.string(for: "settings.nudgeAfter", count: 1, ["1"]), "Nudge after 1 menu use")
        XCTAssertEqual(english.string(for: "settings.nudgeAfter", count: 3, ["3"]), "Nudge after 3 menu uses")
        XCTAssertEqual(english.string(for: "settings.dailyCap", count: 1, ["1"]), "At most 1 nudge per day")
        XCTAssertEqual(english.string(for: "settings.dailyCap", count: 12, ["12"]), "At most 12 nudges per day")
        XCTAssertEqual(english.string(for: "overlay.count", count: 0, ["0"]), "0 shortcuts")
        XCTAssertEqual(english.string(for: "overlay.count", count: 1, ["1"]), "1 shortcut")
        XCTAssertEqual(english.string(for: "nudge.subtitle", count: 1, ["Safari", "1"]), "Safari · 1 menu use this week")
        XCTAssertEqual(english.string(for: "nudge.subtitle", count: 4, ["Safari", "4"]), "Safari · 4 menu uses this week")
        XCTAssertEqual(english.string(for: "stats.learned", count: 1), "shortcut learned")
        XCTAssertEqual(english.string(for: "stats.learned", count: 2), "shortcuts learned")

        let french = shipped("fr")
        XCTAssertEqual(french.string(for: "overlay.count", count: 0, ["0"]), "0 raccourci")
        XCTAssertEqual(french.string(for: "overlay.count", count: 2, ["2"]), "2 raccourcis")
        XCTAssertEqual(shipped("de").string(for: "settings.nudgeAfter", count: 2, ["2"]), "Hinweis nach 2 Menüaufrufen")
        XCTAssertEqual(shipped("pt-BR").string(for: "settings.dailyCap", count: 0, ["0"]), "No máximo 0 dica por dia")
        XCTAssertEqual(shipped("ja").string(for: "overlay.count", count: 1, ["1"]), "ショートカット1件")
    }

    /// Every plural phrase ships both forms in every language, and the European ones differ.
    func testEveryShippedPluralKeyHasBothForms() {
        let english = shipped("en")
        let stems = english.strings.keys.filter { $0.hasSuffix(".one") }.map { String($0.dropLast(4)) }
        XCTAssertGreaterThanOrEqual(stems.count, 8)
        for code in LocalizationManager.supportedCodes {
            let manager = shipped(code)
            for stem in stems {
                XCTAssertNotNil(manager.strings[stem + ".one"], "\(code) \(stem)")
                XCTAssertNotNil(manager.strings[stem + ".other"], "\(code) \(stem)")
                if ["en", "fr", "de", "es", "pt-BR"].contains(code) {
                    XCTAssertNotEqual(manager.strings[stem + ".one"], manager.strings[stem + ".other"], "\(code) \(stem)")
                }
            }
        }
    }

    func testAMissingFormFallsBackToTheLanguagesOtherFormThenThePlainKeyThenEnglish() throws {
        let manager = try custom([
            "English": """
              <string key="files.one">%1 file</string>
              <string key="files.other">%1 files</string>
              <string key="things">%1 things</string>
              <string key="englishOnly.one">%1 English item</string>
              <string key="englishOnly.other">%1 English items</string>
            """,
            "French": """
              <string key="files.other">%1 fichiers</string>
              <string key="things">%1 choses</string>
            """,
        ], language: "fr")

        XCTAssertEqual(manager.string(for: "files", count: 2, ["2"]), "2 fichiers")
        XCTAssertEqual(manager.string(for: "files", count: 1, ["1"]), "1 fichiers", "the language's own text before English")
        XCTAssertEqual(manager.string(for: "things", count: 1, ["1"]), "1 choses")
        XCTAssertEqual(manager.string(for: "englishOnly", count: 0, ["0"]), "0 English items", "English by English's rule")
        XCTAssertEqual(manager.string(for: "englishOnly", count: 1, ["1"]), "1 English item")
        XCTAssertEqual(manager.string(for: "missing", count: 1, ["1"]), "missing")
    }

    // MARK: Numbers

    func testDecimalsFollowTheInterfaceLanguage() {
        let expected: [String: String] = [
            "en": "2.5", "fr": "2,5", "de": "2,5", "es": "2,5",
            "pt-BR": "2,5", "ja": "2.5", "ko": "2.5", "zh-Hans": "2.5",
        ]
        XCTAssertEqual(Set(expected.keys), Set(LocalizationManager.supportedCodes))
        for (code, text) in expected {
            XCTAssertEqual(shipped(code).decimal(2.5), text, code)
        }
        XCTAssertEqual(shipped("de").decimal(3), "3,0")
        XCTAssertEqual(shipped("en").decimal(1.5), "1.5")

        let french = shipped("fr")
        XCTAssertEqual(french.string(for: "settings.hudDuration", [french.decimal(1.5)]), "Afficher la suggestion pendant 1,5 secondes")
    }

    func testTheSystemLanguageDecidesTheFormatOnlyThroughTheLanguageRoteShows() throws {
        let testDefaults = TestDefaults()
        addTeardownBlock { testDefaults.remove() }
        // Swiss German writes 2.5; Rote shows its German table, so it writes 2,5 like the text around it.
        let manager = LocalizationManager(defaults: testDefaults.defaults, bundle: .main, preferredLanguages: { ["de-CH"] })
        XCTAssertEqual(manager.languageCode, "system")
        XCTAssertEqual(manager.displayCode, "de")
        XCTAssertEqual(manager.decimal(2.5), "2,5")

        manager.languageCode = "en"
        XCTAssertEqual(manager.displayCode, "en")
        XCTAssertEqual(manager.decimal(2.5), "2.5")
    }

    func testAnUnknownSavedLanguageShowsAndFormatsEnglish() {
        let manager = shipped("xx")
        XCTAssertEqual(manager.displayCode, "en")
        XCTAssertEqual(manager.decimal(2.5), "2.5")
        XCTAssertEqual(manager.string(for: "settings.itemSpacing", count: 1, ["1"]), "At least 1 hour between nudges for the same item")
    }

    func testWholeNumbersAreGroupedTheLanguagesWay() {
        XCTAssertEqual(shipped("en").number(1_500), "1,500")
        XCTAssertEqual(shipped("de").number(1_500), "1.500")
        XCTAssertEqual(shipped("ja").number(12), "12")
    }

    // MARK: Spoken shortcuts

    private let shiftCommandN = Shortcut(modifiers: [.shift, .command], key: .character("N"))
    private let everyModifierEscape = Shortcut(modifiers: [.control, .option, .shift, .command], key: .special(.escape))
    private let commandF5 = Shortcut(modifiers: [.command], key: .special(.f5))
    private let optionLeft = Shortcut(modifiers: [.option], key: .special(.leftArrow))

    func testShortcutsAreSpokenInTheInterfaceLanguage() {
        let expected: [String: [String]] = [
            "en": ["Shift Command N", "Control Option Shift Command Escape", "Command F5", "Option Left Arrow"],
            "fr": ["Maj Commande N", "Contrôle Option Maj Commande Échap", "Commande F5", "Option Flèche vers la gauche"],
            "de": ["Umschalt Befehl N", "Control Wahl Umschalt Befehl Escape", "Befehl F5", "Wahl Linkspfeil"],
            "es": ["Mayúsculas Comando N", "Control Opción Mayúsculas Comando Escape", "Comando F5", "Opción Flecha izquierda"],
            "ja": ["Shift Command N", "Control Option Shift Command Escape", "Command F5", "Option 左矢印"],
        ]
        for (code, sentences) in expected {
            let manager = shipped(code)
            let spoken = [shiftCommandN, everyModifierEscape, commandF5, optionLeft].map { spokenShortcut($0, localization: manager) }
            XCTAssertEqual(spoken, sentences, code)
        }
    }

    func testEnglishSpeaksExactlyWhatRoteCoreDescribes() {
        let english = shipped("en")
        for special in SpecialKey.allCases {
            let shortcut = Shortcut(modifiers: [.control, .option, .shift, .command], key: .special(special))
            XCTAssertEqual(spokenShortcut(shortcut, localization: english), GlyphFormatter.spokenDescription(shortcut), special.rawValue)
        }
    }

    func testEveryLanguageNamesEveryModifierAndNonFunctionKey() {
        let keys = ["spoken.control", "spoken.option", "spoken.shift", "spoken.command"]
            + SpecialKey.allCases.filter { !$0.isFunctionKey }.map { "spoken.key.\($0.rawValue)" }
        XCTAssertEqual(keys.count, 21)
        for code in LocalizationManager.supportedCodes {
            let manager = shipped(code)
            for key in keys {
                XCTAssertNotNil(manager.strings[key], "\(code) \(key)")
            }
            XCTAssertNil(manager.strings["spoken.key.f1"], "F-keys are read as drawn")
        }
    }

    func testATableWithoutSpokenNamesFallsBackToRoteCoresEnglish() throws {
        let manager = try custom(["English": "<string key=\"other\">x</string>"], language: "en")
        XCTAssertEqual(spokenShortcut(everyModifierEscape, localization: manager), "Control Option Shift Command Escape")
        XCTAssertEqual(spokenShortcut(shiftCommandN, localization: manager), "Shift Command N")
    }

    func testMenuItemsAndTheNudgeAnnouncementSpeakTheShortcutInTheInterfaceLanguage() {
        let french = shipped("fr")
        XCTAssertEqual(spokenMenuItem("Nouvelle fenêtre", shortcut: shiftCommandN, localization: french), "Nouvelle fenêtre, Maj Commande N")
        XCTAssertEqual(spokenMenuItem("Sans raccourci", shortcut: nil, localization: french), "Sans raccourci")

        let record = ItemRecord(item: Fixtures.item(["File", "Save"], "S"))
        XCTAssertEqual(NudgeController.announcement(for: record, localization: french), "Raccourci pour Save\u{00A0}: Commande S", "the translation keeps its no-break space")
        XCTAssertEqual(NudgeController.announcement(for: record, localization: shipped("de")), "Kurzbefehl für Save: Befehl S")
        let noShortcut = ItemRecord(item: MenuItemRecord(bundleID: Fixtures.appA.bundleID, path: ["File", "Close"], shortcut: nil))
        XCTAssertNil(NudgeController.announcement(for: noShortcut, localization: french))
    }

    // MARK: Update errors

    func testEveryUpdateErrorHasAMessageInEveryLanguage() {
        let cases: [(GitHubUpdateChecker.UpdateError, String)] = [
            (.serverError, "update.error.server"),
            (.invalidResponse, "update.error.invalidResponse"),
            (.noDownloadAsset, "update.error.noDownload"),
            (.downloadFailed, "update.error.download"),
            (.extractFailed, "update.error.extract"),
            (.noAppInArchive, "update.error.noApp"),
            (.installFailed("Could not create installer script"), "update.error.install"),
            (.installFailed("Authorization cancelled"), "update.error.installCancelled"),
        ]
        let english = shipped("en")
        for code in LocalizationManager.supportedCodes {
            let manager = shipped(code)
            for (error, key) in cases {
                let message = UpdateErrorMessage.text(for: error, localization: manager)
                XCTAssertEqual(message, manager.string(for: key), "\(code) \(key)")
                XCTAssertNotNil(manager.strings[key], "\(code) \(key)")
                if code != "en" {
                    XCTAssertNotEqual(message, english.string(for: key), "\(code) \(key) is translated")
                }
            }
        }
    }

    func testUpdateErrorMessagesReadInTheInterfaceLanguage() {
        let english = shipped("en")
        let french = shipped("fr")
        XCTAssertEqual(UpdateErrorMessage.text(for: GitHubUpdateChecker.UpdateError.serverError, localization: english),
                       "Could not reach GitHub. Check your internet connection.")
        XCTAssertEqual(UpdateErrorMessage.text(for: GitHubUpdateChecker.UpdateError.serverError, localization: french),
                       "Impossible de joindre GitHub. Vérifiez votre connexion à Internet.")
        XCTAssertEqual(UpdateErrorMessage.text(for: GitHubUpdateChecker.UpdateError.installFailed("Authorization cancelled"), localization: french),
                       "L’installation a été annulée.")
        // The system's own reason for a failed install follows Rote's sentence.
        XCTAssertEqual(UpdateErrorMessage.text(for: GitHubUpdateChecker.UpdateError.installFailed("Opération non autorisée."), localization: french),
                       "Impossible d’installer la mise à jour. Opération non autorisée.")
        // Offline: URLSession's error reads as the unreachable-GitHub message, not in the system's language.
        XCTAssertEqual(UpdateErrorMessage.text(for: URLError(.notConnectedToInternet), localization: french),
                       french.string(for: "update.error.server"))
        // Anything else keeps its own description.
        let other = CocoaError(.fileWriteNoPermission)
        XCTAssertEqual(UpdateErrorMessage.text(for: other, localization: french), other.localizedDescription)
    }

    /// The time is inserted as "13:00" or "1:00 p. m.", so no article before it may assume an hour.
    func testPauseLinesReadRightForEveryHour() {
        for code in LocalizationManager.supportedCodes {
            let text = shipped(code).string(for: "popover.pausedUntil")
            XCTAssertTrue(text.contains("%1"), code)
            for article in [" la %1", " las %1", " a %1", " as %1", " às %1", " à %1"] {
                XCTAssertFalse(text.contains(article), "\(code): \(text)")
            }
        }
    }

    // MARK: Literals

    func testTheEmptyListAndExportNameAreTranslated() {
        let english = shipped("en")
        XCTAssertEqual(english.string(for: "general.none"), "None")
        XCTAssertEqual(english.string(for: "settings.exportFilename"), "rote-state")
        for code in LocalizationManager.supportedCodes where code != "en" {
            let manager = shipped(code)
            XCTAssertNotEqual(manager.string(for: "general.none"), "None", code)
            XCTAssertNotNil(manager.strings["settings.exportFilename"], code)
            XCTAssertFalse(manager.string(for: "settings.exportFilename").contains("/"), code)
        }
    }
}
