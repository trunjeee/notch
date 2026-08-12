import Foundation
import Combine

/// Words the switcher should never touch — brand names, handles, domains,
/// anything that looks like gibberish in either language on purpose.
///
/// Backed by a plain text file (one word per line) so it survives restarts:
/// `~/Library/Application Support/notchbytrj/switcher-exceptions.txt`. This
/// is the single live copy — the menu bar's "Switcher Exceptions" window
/// edits the same instance `KeyboardMonitor` reads from, so changes apply
/// without restarting the app.
final class ExceptionListStore: ObservableObject {
    static let shared = ExceptionListStore()

    @Published private(set) var words: [String] = []

    private let fileURL: URL
    private let builtIns = ["trj", "trj.at"]

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notchbytrj", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("switcher-exceptions.txt")
        load()
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            words = builtIns
            save()
            return
        }
        let lines = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        words = lines.isEmpty ? builtIns : lines
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
