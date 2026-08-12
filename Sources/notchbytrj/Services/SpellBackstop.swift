import AppKit

/// Whole-word validity check using macOS's built-in spell checker, used as a
/// backstop at word boundaries for cases the instant bigram heuristic missed
/// (e.g. short words).
enum SpellBackstop {
    private static let checker = NSSpellChecker.shared

    static func isValidWord(_ word: String, language: AppLanguage) -> Bool {
        guard word.count >= 2 else { return true } // too short to judge, don't block
        let language = (language == .russian) ? "ru" : "en"
        let range = checker.checkSpelling(of: word, startingAt: 0, language: language, wrap: false, inSpellDocumentWithTag: 0, wordCount: nil)
        return range.location == NSNotFound
    }

    /// The system's own top spelling suggestion for a misspelled word —
    /// same mechanism as the red-squiggle correction menu in any Mac text
    /// field, just applied automatically instead of waiting for a click.
    static func topSuggestion(for word: String, language: AppLanguage) -> String? {
        let languageCode = (language == .russian) ? "ru" : "en"
        let range = NSRange(location: 0, length: word.utf16.count)
        let guesses = checker.guesses(forWordRange: range, in: word, language: languageCode, inSpellDocumentWithTag: 0)
        return guesses?.first
    }
}
