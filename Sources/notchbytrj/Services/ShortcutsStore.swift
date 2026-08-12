import Foundation

/// Runs macOS Shortcuts by name via the public `shortcuts` CLI — no
/// scripting dictionary, no Automation permission, just a subprocess.
/// Which ones show up in the panel is user-picked and persisted, since
/// nobody wants every shortcut they've ever made cluttering one tab.
final class ShortcutsStore: ObservableObject {
    static let shared = ShortcutsStore()

    @Published private(set) var available: [String] = []
    @Published private(set) var selected: [String] = []

    private let fileURL: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notchbytrj", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("quick-actions.txt")
        load()
        refreshAvailable()
    }

    private func load() {
        guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
            selected = []
            return
        }
        selected = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private func save() {
        try? (selected.joined(separator: "\n") + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
    }

    func refreshAvailable() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["list"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(data: data, encoding: .utf8) ?? ""
        available = text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func add(_ name: String) {
        guard !selected.contains(name) else { return }
        selected.append(name)
        save()
    }

    func remove(_ name: String) {
        selected.removeAll { $0 == name }
        save()
    }

    /// Fire-and-forget: a shortcut that needs to report back does so through
    /// its own notification or UI, not through this panel.
    func run(_ name: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        try? process.run()
    }
}
