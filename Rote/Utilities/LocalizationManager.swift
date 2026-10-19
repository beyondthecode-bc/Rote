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

    /// "system" or one of `supportedCodes`.
    var languageCode: String {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: Self.defaultsKey)
            reload()
        }
    }

    private init() {
        languageCode = UserDefaults.standard.string(forKey: Self.defaultsKey) ?? "system"
        fallback = Self.loadXML("English")
        reload()
    }

    func string(for key: String) -> String {
        strings[key] ?? fallback[key] ?? key
    }

    /// Replaces %1, %2, … with `values` in order.
    func string(for key: String, _ values: [String]) -> String {
        var text = string(for: key)
        for (index, value) in values.enumerated() {
            text = text.replacingOccurrences(of: "%\(index + 1)", with: value)
        }
        return text
    }

    private func reload() {
        let code = languageCode == "system" ? Self.systemCode() : languageCode
        strings = Self.loadXML(Self.fileMap[code] ?? "English")
        Logger.ui.info("Loaded \(self.strings.count) strings for \(code, privacy: .public)")
    }

    static func systemCode() -> String {
        for language in Locale.preferredLanguages {
            if supportedCodes.contains(language) { return language }
            if language.hasPrefix("pt") { return "pt-BR" }
            if language.hasPrefix("zh") { return "zh-Hans" }
            let prefix = String(language.prefix(2))
            if supportedCodes.contains(prefix) { return prefix }
        }
        return "en"
    }

    nonisolated private static func loadXML(_ filename: String) -> [String: String] {
        guard let url = Bundle.main.url(forResource: filename, withExtension: "xml", subdirectory: "languages"),
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
            strings[key] = currentValue
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
