import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class LocalizationManager {
    static let shared = LocalizationManager()

    static let supportedCodes = ["en", "fr", "de", "es", "ja", "ko", "pt-BR", "zh-Hans"]

    private static let fileMap: [String: String] = [
        "en": "English", "fr": "French", "de": "German", "es": "Spanish",
        "ja": "Japanese", "ko": "Korean", "pt-BR": "Portuguese", "zh-Hans": "Chinese",
    ]

    private static let defaultsKey = "rote.language"

    private(set) var strings: [String: String] = [:]
    /// The supported code whose table is loaded: the chosen language, or the system's match
    /// while the choice is "system". Plural forms and numbers follow it, never the system region.
    private(set) var displayCode = "en"
    @ObservationIgnored private var fallback: [String: String] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    /// Holds `languages/<Name>.xml`.
    @ObservationIgnored private let bundle: Bundle
    /// The system's languages, read on every reload while the choice is "system".
    @ObservationIgnored private let preferredLanguages: () -> [String]

    /// "system" or one of `supportedCodes`.
    var languageCode: String {
        didSet {
            defaults.set(languageCode, forKey: Self.defaultsKey)
            reload()
        }
    }

    /// The app uses `shared`; tests pass their own defaults, string tables and system languages.
    init(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main,
        preferredLanguages: @escaping () -> [String] = { Locale.preferredLanguages }
    ) {
        self.defaults = defaults
        self.bundle = bundle
        self.preferredLanguages = preferredLanguages
        languageCode = defaults.string(forKey: Self.defaultsKey) ?? "system"
        fallback = Self.loadXML("English", in: bundle)
        reload()
    }

    func string(for key: String) -> String {
        strings[key] ?? fallback[key] ?? key
    }

    /// Replaces %1 … %9 with `values` in one left-to-right pass, so a "%2" inside an inserted
    /// value (a menu title, an app name) is never substituted again. Out-of-range placeholders stay as written.
    func string(for key: String, _ values: [String]) -> String {
        Self.fill(string(for: key), values)
    }

    /// Whole-number plural categories. Rote's languages need two: CLDR's "one" and "other".
    enum PluralCategory: String, Sendable {
        case one, other
    }

    /// The category of `count` in `language`: English, German and Spanish say "one" for 1 only,
    /// French and Brazilian Portuguese for 0 and 1, and Japanese, Korean and Chinese never.
    nonisolated static func pluralCategory(for count: Int, language: String) -> PluralCategory {
        switch language {
        case "fr", "pt-BR": return count == 0 || count == 1 ? .one : .other
        case "ja", "ko", "zh-Hans": return .other
        default: return count == 1 ? .one : .other
        }
    }

    /// `<key>.one` or `<key>.other`, whichever the display language's rule picks for `count`.
    /// A table that lacks that form uses its own `.other`, then its plain `key`; only then the
    /// English table, by English's rule, so a translation never shows English for a missing "one".
    func string(for key: String, count: Int) -> String {
        let form = Self.pluralCategory(for: count, language: displayCode)
        if let text = strings["\(key).\(form.rawValue)"] ?? strings["\(key).other"] ?? strings[key] {
            return text
        }
        let englishForm = Self.pluralCategory(for: count, language: "en")
        return fallback["\(key).\(englishForm.rawValue)"] ?? fallback["\(key).other"] ?? fallback[key] ?? key
    }

    /// The plural form for `count`, with %1 … %9 filled in as `string(for:_:)` does.
    func string(for key: String, count: Int, _ values: [String]) -> String {
        Self.fill(string(for: key, count: count), values)
    }

    /// The locale of the display language. Numbers use it, never the system region, so a
    /// decimal reads like the sentence around it ("1,5 secondes" in French on a US Mac).
    var locale: Locale { Locale(identifier: displayCode) }

    /// A whole number grouped the display language's way: "1,500" in English, "1.500" in German.
    func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    /// A decimal with exactly `fractionDigits` digits after the display language's separator.
    func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
    }

    /// A time of day written the display language's way, on the 12- or 24-hour clock of `clock`
    /// (the Mac's region and its 24-hour setting): "1:05 p. m." in Spanish and "午後1:05" in
    /// Japanese on a US Mac, "13:05" in English on a German one.
    func time(_ date: Date, clock: Locale = .current) -> String {
        var components = Locale.Components(locale: locale)
        components.hourCycle = clock.hourCycle
        return date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: Locale(components: components)))
    }

    nonisolated private static func fill(_ template: String, _ values: [String]) -> String {
        let characters = Array(template)
        var text = ""
        var index = 0
        while index < characters.count {
            if characters[index] == "%", index + 1 < characters.count, characters[index + 1].isASCII,
               let number = characters[index + 1].wholeNumberValue, number >= 1, number <= values.count {
                text += values[number - 1]
                index += 2
            } else {
                text.append(characters[index])
                index += 1
            }
        }
        return text
    }

    private func reload() {
        let chosen = languageCode == "system" ? Self.systemCode(preferred: preferredLanguages()) : languageCode
        let code = Self.fileMap[chosen] == nil ? "en" : chosen
        displayCode = code
        strings = Self.loadXML(Self.fileMap[code] ?? "English", in: bundle)
        Logger.ui.info("Loaded \(self.strings.count) strings for \(code, privacy: .public)")
    }

    /// The supported code that best matches `preferred`, using Foundation's localization matching:
    /// "kok" never becomes "ko", Traditional Chinese never becomes Simplified, and an unsupported
    /// first choice falls through to the next preferred language. English when nothing matches.
    static func systemCode(preferred: [String] = Locale.preferredLanguages) -> String {
        Bundle.preferredLocalizations(from: supportedCodes, forPreferences: preferred).first ?? "en"
    }

    nonisolated private static func loadXML(_ filename: String, in bundle: Bundle) -> [String: String] {
        guard let url = bundle.url(forResource: filename, withExtension: "xml", subdirectory: "languages"),
              let data = try? Data(contentsOf: url)
        else { return [:] }
        let delegate = StringsXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }
}

private final class StringsXMLParserDelegate: NSObject, XMLParserDelegate {
    var strings: [String: String] = [:]
    private var currentKey: String?
    private var currentValue = ""

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if elementName == "string", let key = attributes["key"] {
            currentKey = key
            currentValue = ""
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentKey != nil { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?) {
        if elementName == "string", let key = currentKey {
            // An empty value would hide the English fallback behind blank text.
            let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { strings[key] = value }
            currentKey = nil
            currentValue = ""
        }
    }
}

@MainActor
func l(_ key: String) -> String {
    LocalizationManager.shared.string(for: key)
}

@MainActor
func l(_ key: String, _ values: String...) -> String {
    LocalizationManager.shared.string(for: key, values)
}

/// The plural form of `key` for `count`. The count is not inserted by itself: pass it,
/// formatted with `number(_:)`, among `values` at the placeholder the phrase uses.
@MainActor
func l(_ key: String, count: Int, _ values: String...) -> String {
    LocalizationManager.shared.string(for: key, count: count, values)
}

/// A whole number in the display language's format.
@MainActor
func number(_ value: Int) -> String {
    LocalizationManager.shared.number(value)
}

/// A decimal in the display language's format, one digit after the separator by default.
@MainActor
func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
    LocalizationManager.shared.decimal(value, fractionDigits: fractionDigits)
}
