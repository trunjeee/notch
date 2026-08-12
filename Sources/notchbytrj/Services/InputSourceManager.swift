import Carbon
import Foundation

enum AppLanguage {
    case english
    case russian
}

/// Reads and switches the active keyboard input source (layout) via the
/// Text Input Sources API (Carbon TIS*).
///
/// Matched by declared language code (`kTISPropertyInputSourceLanguages`),
/// not by source name: English layouts are not consistently named "U.S." —
/// this machine's is literally called "ABC" — so name matching silently
/// fails to find a target and `switchTo` becomes a no-op.
final class InputSourceManager {

    private func keyboardSources() -> [TISInputSource] {
        guard let list = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list.filter { source in
            guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsSelectCapable) else { return false }
            return Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue() == kCFBooleanTrue
        }
    }

    private func languages(of source: TISInputSource) -> [String] {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as [AnyObject]
        return array.compactMap { $0 as? String }
    }

    private func inputSource(forLanguagePrefix prefix: String) -> TISInputSource? {
        keyboardSources().first { source in
            languages(of: source).contains { $0.hasPrefix(prefix) }
        }
    }

    func currentLanguage() -> AppLanguage {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return .english
        }
        return languages(of: source).contains { $0.hasPrefix("ru") } ? .russian : .english
    }

    @discardableResult
    func switchTo(_ language: AppLanguage) -> Bool {
        let prefix = (language == .russian) ? "ru" : "en"
        guard let source = inputSource(forLanguagePrefix: prefix) else { return false }
        TISSelectInputSource(source)
        return true
    }
}
