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
    @ObservationIgnored private var fallback: [String: String] = [:]
    @ObservationIgnored private let defaults: UserDefaults
    /// Holds `languages/<Name>.xml`.
    @ObservationIgnored private let bundle: Bundle

    /// "system" or one of `supportedCodes`.
    var languageCode: String {
        didSet {
            defaults.set(languageCode, forKey: Self.defaultsKey)
            reload()
        }
    }

    /// The app uses `shared`; tests pass their own defaults and string tables.
    init(defaults: UserDefaults = .standard, bundle: Bundle = .main) {
        self.defaults = defaults
        self.bundle = bundle
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
        let template = Array(string(for: key))
        var text = ""
        var index = 0
        while index < template.count {
            if template[index] == "%", index + 1 < template.count, template[index + 1].isASCII,
               let number = template[index + 1].wholeNumberValue, number >= 1, number <= values.count {
                text += values[number - 1]
                index += 2
            } else {
                text.append(template[index])
                index += 1
            }
        }
        return text
    }

    private func reload() {
        let code = languageCode == "system" ? Self.systemCode() : languageCode
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
