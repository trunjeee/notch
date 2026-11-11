import AppKit

/// Types a finished string into whatever field is focused, the same way the
/// layout switcher re-types corrected words: a synthetic CGEvent carrying a
/// Unicode string. Any text field that accepts real typing accepts this —
/// secure (password) fields excepted, which swallow synthetic input by
/// design.
///
/// The events carry KeyboardMonitor's injected marker, so dictated text is
/// never read back by the layout switcher as words to "correct".
enum TextInjector {

    static func insert(_ string: String) {
        guard !string.isEmpty,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        let utf16 = Array(string.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.setIntegerValueField(.eventSourceUserData, value: KeyboardMonitor.injectedMarker)
        up.setIntegerValueField(.eventSourceUserData, value: KeyboardMonitor.injectedMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
