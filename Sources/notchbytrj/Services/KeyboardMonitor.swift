import AppKit
import ApplicationServices
import Carbon.HIToolbox

private struct TypedKey {
    let keycode: CGKeyCode
    let shift: Bool
    let typedChar: Character
}

final class KeyboardMonitor {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let inputSources = InputSourceManager()
    private var buffer: [TypedKey] = []
    /// True only right after a real word was ended by a plain space — the
    /// one case where a comma is safe to insert before the next trigger
    /// word. Punctuation right before the word (". но", "! а") disqualifies
    /// it, and so does two boundary characters in a row.
    private var commaEligible = false

    /// Marks CGEvents this class posts itself, so its own event tap doesn't
    /// pick them back up as real typing. A `.listenOnly` tap can't just
    /// suppress the injected keystrokes it sees — since it never blocks
    /// anything — and the events land back in this same callback a moment
    /// later. Without this tag, a correction's own backspace/retype was
    /// occasionally read as new input and triggered a second, wrong
    /// correction right on top of the first.
    private static let injectedMarker: Int64 = 0x4E54524A

    var isEnabled: Bool = true
    /// Separate from `isEnabled`: fixing a wrong layout is nearly always
    /// right, but guessing at a same-language typo can misfire on names,
    /// slang, or short words the dictionary doesn't know — worth letting
    /// someone run one without the other.
    var spellAutocorrectEnabled: Bool = false

    func start() {
        // Clicks are watched too, purely to drop tracked state on them: a
        // click can move the cursor anywhere in the document without
        // touching the keyboard at all, and this class has no way to read
        // what's actually there. Better to forget what it assumed about the
        // surrounding text than act on a guess that's gone stale — that
        // gap was what let the comma helper double up on an existing comma
        // after the user clicked back in next to one.
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)
            | (1 << CGEventType.otherMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(event: event, type: type)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("notchbytrj-switcher: failed to create event tap — check Accessibility/Input Monitoring permissions")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("notchbytrj-switcher: event tap started, trusted=\(AXIsProcessTrusted())")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(event: CGEvent, type: CGEventType) {
        guard isEnabled else { return }

        guard type == .keyDown else {
            // A click — see the comment on the tap's event mask above.
            buffer.removeAll()
            commaEligible = false
            return
        }
        if event.getIntegerValueField(.eventSourceUserData) == Self.injectedMarker { return }

        // A held key (typamatic repeat, or the press-and-hold accent picker
        // for é/ё/etc.) resends the same keyDown many times. Treating each
        // repeat as a new letter both spams the buffer with duplicates and
        // can trigger a correction mid-hold, stomping on whatever the OS's
        // own accent popup or repeat was doing — which read as "can't type
        // this word at all".
        if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return }

        let flags = event.flags
        // Ignore combos with Cmd/Ctrl/Option — those are shortcuts, not text.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            buffer.removeAll()
            commaEligible = false
            return
        }

        let keycode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let shift = flags.contains(.maskShift)

        if keycode == CGKeyCode(kVK_Delete) {
            if !buffer.isEmpty { buffer.removeLast() }
            return
        }

        if !LayoutTables.letterKeycodes.contains(keycode) {
            // Word boundary (space/enter/punctuation/arrow/etc.) — run the
            // dictionary backstop on the just-finished word, then reset.
            //
            // This is a .listenOnly tap: the boundary key (e.g. the space)
            // is already on its way to the frontmost app by the time this
            // callback runs and cannot be intercepted. If a correction fires,
            // it has to delete that character too and retype it after the
            // fix, or the backspaces eat into the word instead of the space.
            let boundaryChar = NSEvent(cgEvent: event)?.characters?.first
            let hadWord = !buffer.isEmpty
            checkWordBoundary(boundaryChar: boundaryChar, commaEligible: commaEligible)
            buffer.removeAll()
            commaEligible = hadWord && boundaryChar == " "
            return
        }

        guard let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.characters, let typedChar = chars.first else {
            return
        }
        buffer.append(TypedKey(keycode: keycode, shift: shift, typedChar: typedChar))
    }

    // MARK: - Word-boundary checks

    /// Everything happens once a word is finished, not while it's still
    /// being typed. An earlier version also corrected mid-word, matching
    /// how Caramba Switcher looks — but the bigram-based guess it relied on
    /// to judge an *unfinished* word was exactly what made short or
    /// ambiguous-looking words (cegth, heccrbq, тот) flip unpredictably or
    /// get half-corrected. Checking only complete words trades that
    /// "before you finish typing" feel for actually being reliable, using
    /// the system spell checker instead of a guess.
    private func checkWordBoundary(boundaryChar: Character?, commaEligible: Bool) {
        guard !buffer.isEmpty else { return }

        let typed = String(buffer.map { $0.typedChar })
        guard !ExceptionListStore.shared.contains(typed) else { return }

        let currentLang = inputSources.currentLanguage()
        let otherTable: [CGKeyCode: (Character, Character)] = (currentLang == .english) ? LayoutTables.ru : LayoutTables.us
        let remapped = String(buffer.compactMap { LayoutTables.char(for: $0.keycode, in: otherTable, shift: $0.shift) })
        let otherLang: AppLanguage = (currentLang == .english) ? .russian : .english

        // Not every key holds a letter in both layouts (о→j but б→"," rather
        // than a letter) — remapping a real word can land on a string with a
        // stray punctuation mark in the middle. Handing that to the spell
        // checker is what produced the half-corrected "jibбка": it read the
        // comma as a word separator and judged the two pieces on either side
        // of it separately, one of which ("jib") happens to be a real
        // English word on its own. A remap with a non-letter in it was never
        // going to be the real word anyway, so it's rejected outright,
        // before the spell checker gets a chance to be clever about it.
        let remappedIsWordShaped = remapped.count == buffer.count && remapped.allSatisfy { $0.isLetter }

        let typedValid = isValid(typed, language: currentLang)
        let remappedValid = remappedIsWordShaped && isValid(remapped, language: otherLang)

        if !typedValid, remappedValid {
            correct(replacement: remapped, targetLang: otherLang, boundaryChar: boundaryChar)
            return
        }

        // Invalid in this language and the other layout doesn't explain it
        // either — a plain typo, not a wrong-layout word. Only a same-
        // language guess helps here, and only if that guess is turned on.
        if spellAutocorrectEnabled, !typedValid, buffer.count >= 3,
           let suggestion = SpellBackstop.topSuggestion(for: typed, language: currentLang),
           suggestion.lowercased() != typed.lowercased() {
            correct(replacement: suggestion, targetLang: currentLang, boundaryChar: boundaryChar)
            return
        }

        // Below here: the word is fine as typed — Russian-specific touch-ups
        // that have nothing to do with the wrong layout.
        if buffer.count >= 2, currentLang == .russian, let fixed = YoWords.corrected(typed), fixed != typed {
            correct(replacement: fixed, targetLang: .russian, boundaryChar: boundaryChar)
            return
        }

        if currentLang == .russian, CommaAssistant.needsCommaBefore(typed), commaEligible {
            insertLeadingComma(word: typed, boundaryChar: boundaryChar)
            return
        }
    }

    /// The system spell checker alone gets two cases wrong in ways that are
    /// worth special-casing rather than living with:
    ///  - short tech abbreviations (js, css, html, api, ...) aren't real
    ///    dictionary words, so whether one "passes" ends up depending on
    ///    accidents of the user's personal learned-words list rather than
    ///    being consistent between them;
    ///  - single letters are too short for the spell checker to judge at
    ///    all (it treats anything under 2 characters as automatically
    ///    valid), which silently disabled correction for one-letter "words"
    ///    like the Russian "и"/"а" typed on the wrong layout.
    private func isValid(_ word: String, language: AppLanguage) -> Bool {
        let lower = word.lowercased()
        if language == .english, Self.knownTechWords.contains(lower) { return true }
        // Not gated on `language`: the word's own script (Latin vs Cyrillic)
        // already separates a Latin custom word from ever matching Cyrillic
        // text, so a list holding both English and Russian entries needs no
        // per-word language tag to stay unambiguous.
        if KnownWordsStore.shared.contains(lower) { return true }
        if word.count == 1, let letter = lower.first {
            let known = (language == .english) ? Self.validEnglishSingleLetters : Self.validRussianSingleLetters
            return known.contains(letter)
        }
        return SpellBackstop.isValidWord(word, language: language)
    }

    private static let knownTechWords: Set<String> = [
        "js", "css", "html", "php", "sql", "api", "url", "json", "xml", "http", "https",
        "ui", "ux", "ip", "os", "cpu", "gpu", "ram", "usb", "pdf", "png", "jpg", "jpeg", "gif", "svg",
        "git", "npm", "cli", "sdk", "ios", "macos", "es6", "jsx", "tsx", "yaml", "toml",
        "curl", "ssh", "ftp", "dns", "seo", "cms", "crm", "saas", "ide", "orm", "jwt", "cors", "cdn", "dom",
    ]
    private static let validEnglishSingleLetters: Set<Character> = ["a", "i"]
    private static let validRussianSingleLetters: Set<Character> = ["а", "и", "в", "к", "с", "о", "у", "я"]

    // MARK: - Correction

    private func correct(replacement: String, targetLang: AppLanguage, boundaryChar: Character? = nil) {
        NSLog("notchbytrj-switcher: correcting '\(String(buffer.map { $0.typedChar }))' -> '\(replacement)' target=\(targetLang)")

        // The boundary character (if any) is already on screen, past the
        // word — it has to come out too, and go back in after the fix.
        let deleteCount = buffer.count + (boundaryChar != nil ? 1 : 0)
        deleteBackward(deleteCount)

        inputSources.switchTo(targetLang)
        var finalText = replacement
        if let boundaryChar { finalText.append(boundaryChar) }
        usleep(4_000)
        postUnicodeString(finalText)
        SwitchSound.play()

        buffer.removeAll()
    }

    /// The word is fine, but it needs a comma in front of it — and the space
    /// that's already there, from the word before, isn't part of this
    /// word's buffer. Both it and the word's own trailing boundary have to
    /// be deleted and replaced together, or the comma lands on the wrong
    /// side of the space.
    private func insertLeadingComma(word: String, boundaryChar: Character?) {
        guard let boundaryChar else { return }
        NSLog("notchbytrj-switcher: inserting comma before '\(word)'")

        let deleteCount = buffer.count + 2 // word + its trailing boundary + the preceding space
        deleteBackward(deleteCount)

        usleep(4_000)
        postUnicodeString(", \(word)\(boundaryChar)")
        SwitchSound.play()

        buffer.removeAll()
    }

    /// Fired as a tight loop of synthetic events with no gap at all, some
    /// apps' own key-processing (spell-check-as-you-type, undo coalescing)
    /// can't keep up and silently drop a delete or two — which is exactly
    /// how a correction ends up half old text, half new ("jibбка" instead
    /// of "ошибка"). A couple of milliseconds between presses costs nothing
    /// anyone can perceive and gives the target app time to actually catch
    /// each one.
    private func deleteBackward(_ count: Int) {
        for _ in 0..<count {
            postKey(keycode: CGKeyCode(kVK_Delete))
            usleep(3_000)
        }
    }

    private func postKey(keycode: CGKeyCode) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keycode, keyDown: false) else { return }
        down.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func postUnicodeString(_ string: String) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return }
        let utf16 = Array(string.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
        up.setIntegerValueField(.eventSourceUserData, value: Self.injectedMarker)
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
