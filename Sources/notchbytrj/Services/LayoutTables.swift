import CoreGraphics

/// Maps physical key positions (macOS virtual keycodes) to the character each
/// layout produces there. Both layouts share the same physical key positions,
/// which is what lets us "translate" a buffer typed in the wrong layout.
enum LayoutTables {

    /// US QWERTY: keycode -> (unshifted, shifted)
    static let us: [CGKeyCode: (Character, Character)] = [
        0x00: ("a", "A"), 0x01: ("s", "S"), 0x02: ("d", "D"), 0x03: ("f", "F"),
        0x05: ("g", "G"), 0x04: ("h", "H"), 0x06: ("z", "Z"), 0x07: ("x", "X"),
        0x08: ("c", "C"), 0x09: ("v", "V"), 0x0B: ("b", "B"), 0x0C: ("q", "Q"),
        0x0D: ("w", "W"), 0x0E: ("e", "E"), 0x0F: ("r", "R"), 0x10: ("y", "Y"),
        0x11: ("t", "T"), 0x1F: ("o", "O"), 0x20: ("u", "U"), 0x22: ("i", "I"),
        0x23: ("p", "P"), 0x25: ("l", "L"), 0x26: ("j", "J"), 0x28: ("k", "K"),
        0x2D: ("n", "N"), 0x2E: ("m", "M"),
        0x29: (";", ":"), 0x27: ("'", "\""), 0x2B: (",", "<"), 0x2F: (".", ">"),
        0x2C: ("/", "?"), 0x21: ("[", "{"), 0x1E: ("]", "}"), 0x2A: ("\\", "|"),
        0x32: ("`", "~"),
        0x12: ("1", "!"), 0x13: ("2", "@"), 0x14: ("3", "#"), 0x15: ("4", "$"),
        0x17: ("5", "%"), 0x16: ("6", "^"), 0x1A: ("7", "&"), 0x1C: ("8", "*"),
        0x19: ("9", "("), 0x1D: ("0", ")"), 0x1B: ("-", "_"), 0x18: ("=", "+"),
    ]

    /// Russian ЙЦУКЕН, same physical keys: keycode -> (unshifted, shifted)
    static let ru: [CGKeyCode: (Character, Character)] = [
        0x00: ("ф", "Ф"), 0x01: ("ы", "Ы"), 0x02: ("в", "В"), 0x03: ("а", "А"),
        0x05: ("п", "П"), 0x04: ("р", "Р"), 0x06: ("я", "Я"), 0x07: ("ч", "Ч"),
        0x08: ("с", "С"), 0x09: ("м", "М"), 0x0B: ("и", "И"), 0x0C: ("й", "Й"),
        0x0D: ("ц", "Ц"), 0x0E: ("у", "У"), 0x0F: ("к", "К"), 0x10: ("н", "Н"),
        0x11: ("е", "Е"), 0x1F: ("щ", "Щ"), 0x20: ("г", "Г"), 0x22: ("ш", "Ш"),
        0x23: ("з", "З"), 0x25: ("д", "Д"), 0x26: ("о", "О"), 0x28: ("л", "Л"),
        0x2D: ("т", "Т"), 0x2E: ("ь", "Ь"),
        0x29: ("ж", "Ж"), 0x27: ("э", "Э"), 0x2B: ("б", "Б"), 0x2F: ("ю", "Ю"),
        0x2C: (".", ","), 0x21: ("х", "Х"), 0x1E: ("ъ", "Ъ"), 0x2A: ("\\", "/"),
        0x32: ("ё", "Ё"),
        0x12: ("1", "!"), 0x13: ("2", "\""), 0x14: ("3", "№"), 0x15: ("4", ";"),
        0x17: ("5", "%"), 0x16: ("6", ":"), 0x1A: ("7", "?"), 0x1C: ("8", "*"),
        0x19: ("9", "("), 0x1D: ("0", ")"), 0x1B: ("-", "_"), 0x18: ("=", "+"),
    ]

    /// Every keycode that carries a letter in *either* layout — used to
    /// decide whether a keystroke belongs to a "word" for buffering
    /// purposes. This has to be the union, not the intersection: the
    /// Russian alphabet has 33 letters against QWERTY's 26 keys, so seven of
    /// them (ё, ж, э, б, ю, х, ъ) sit on keys that are punctuation in the US
    /// layout. Treating those as "not a letter" was splitting any word that
    /// contained one right down the middle — "ошибка" broke into "оши" and
    /// "бка" exactly at "б" — because a punctuation key looks like a word
    /// boundary to this class.
    static let letterKeycodes: Set<CGKeyCode> = [
        0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F,
        0x10, 0x11, 0x1F, 0x20, 0x22, 0x23, 0x25, 0x26, 0x28, 0x2D, 0x2E,
        0x32, // ё
        0x29, // ж
        0x27, // э
        0x2B, // б
        0x2F, // ю
        0x21, // х
        0x1E, // ъ
    ]

    static func char(for keycode: CGKeyCode, in table: [CGKeyCode: (Character, Character)], shift: Bool) -> Character? {
        guard let pair = table[keycode] else { return nil }
        return shift ? pair.1 : pair.0
    }
}
