import Foundation

/// Deliberately minimal comma helper: only the cases where a comma is
/// (almost) always correct regardless of sentence structure — relative
/// "который" in any form, and the contrastive "но". No participial or
/// adverbial-participle clause detection (деепричастные/причастные
/// обороты) — that needs real grammatical parsing to avoid getting commas
/// wrong as often as right, which is worse than not helping at all.
enum CommaAssistant {
    private static let triggers: Set<String> = [
        "который", "которая", "которое", "которые",
        "которого", "которой", "которых", "которому", "которым", "которыми", "котором",
        "но", "а",
    ]

    static func needsCommaBefore(_ word: String) -> Bool {
        triggers.contains(word.lowercased())
    }
}
