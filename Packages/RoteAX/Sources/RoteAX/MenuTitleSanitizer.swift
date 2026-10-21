import Foundation

/// Cleans a title read from another app before it enters a record, the state file, the log or a
/// view (audit L4). Accessibility hands Rote whatever the app put in its menu: a document name of
/// any length, bidi overrides that reverse the text around it, control characters.
public enum MenuTitleSanitizer {
    /// Unicode scalars a title keeps. The longest real menu titles (a recent document's name) are
    /// far shorter; the sheet truncates anything longer in the middle.
    public static let maxScalars = 256

    /// Zero-width joiner and non-joiner: format characters that emoji sequences (👨‍👩‍👧) and
    /// Persian, Indic and other scripts need for their letters to render correctly.
    private static let keptFormatScalars: Set<Unicode.Scalar> = ["\u{200C}", "\u{200D}"]

    /// Strips control (Cc) and format (Cf) characters, bidi overrides, embeddings and isolates
    /// among them; control whitespace (tab, newline) becomes a space; trims; then caps the result
    /// at `maxScalars`, on a character boundary so no combining mark is cut from its base.
    public static func sanitize(_ raw: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for scalar in raw.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .control:
                if scalar.properties.isWhitespace { cleaned.append(" ") }
            case .format:
                if keptFormatScalars.contains(scalar) { cleaned.append(scalar) }
            default:
                cleaned.append(scalar)
            }
        }
        let trimmed = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.count > maxScalars else { return trimmed }
        var capped = ""
        var count = 0
        for character in trimmed {
            let width = character.unicodeScalars.count
            guard count + width <= maxScalars else { break }
            capped.append(character)
            count += width
        }
        return capped.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
