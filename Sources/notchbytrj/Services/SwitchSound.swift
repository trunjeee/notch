import AppKit

/// The sound played on every correction. Looks for a bundled custom clip
/// first (`Resources/SwitchSound.{mp3,wav,aiff,m4a}` — copied into the app
/// bundle by `Scripts/bundle.sh`), falling back to the system "Tink" sound
/// when none is provided.
enum SwitchSound {
    private static let sound: NSSound? = {
        let extensions = ["mp3", "wav", "aiff", "m4a"]
        for ext in extensions {
            if let url = Bundle.main.url(forResource: "SwitchSound", withExtension: ext),
               let sound = NSSound(contentsOf: url, byReference: true) {
                return sound
            }
        }
        return NSSound(named: "Tink")
    }()

    static func play() {
        sound?.play()
    }
}
