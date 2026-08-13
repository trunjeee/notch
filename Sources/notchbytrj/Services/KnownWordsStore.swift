import Foundation
import Combine

/// The opposite of `ExceptionListStore`: not "never touch this word", but
/// "this is a real English word even though the system dictionary has never
/// heard of it" — a personal domain, a brand, a handle. Without an entry
/// here, something like "trj" typed on the wrong layout has no dictionary
/// backing on either side and never gets corrected either way; with one, it
/// corrects to English exactly like a common word would.
///
/// `~/Library/Application Support/notchbytrj/switcher-known-words.txt`,
/// one word per line — same live-editing setup as the exceptions list.
final class KnownWordsStore: ObservableObject {
    static let shared = KnownWordsStore()

    @Published private(set) var words: [String] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notchbytrj", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("switcher-known-words.txt")
        load()
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            words = []
            return
        }
        words = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        try? (words.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func contains(_ word: String) -> Bool {
        words.contains { $0.caseInsensitiveCompare(word) == .orderedSame }
    }

    func add(_ word: String) {
        let trimmed = word.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !contains(trimmed) else { return }
        words.append(trimmed)
        words.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        save()
    }

    func remove(at offsets: IndexSet) {
        words.remove(atOffsets: offsets)
        save()
    }
}
