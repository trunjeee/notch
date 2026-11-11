# Notch by trj

*English · [Русский](README.ru.md)*

A native SwiftUI/AppKit menu bar app that turns the MacBook notch into a
working panel — invisible at rest, and on hover it unfolds into a player, a
file shelf, clipboard history, snippets, your next meetings, translation, and
scratch notes — plus a RU/EN keyboard layout auto-switcher, hold-right-Option
voice dictation, and a handful of system-monitoring and productivity tabs
added on top.

macOS 15 or newer. Local-only: no accounts, no servers, no telemetry.

## Based on Cyclop

This app started as a fork of **[Cyclop](https://github.com/akalikbergenov/cyclop)**
by [akalikbergenov](https://github.com/akalikbergenov), released under the MIT
license. Cyclop is the notch panel itself — the player, the file shelf,
clipboard history, snippets, calendar, offline translation, and scratch
notes — along with the low-level mechanics that make a borderless,
click-through panel behave like a native piece of macOS: hover detection,
window geometry tied to the actual notch size, cursor handling, and a Now
Playing bridge that reads track info from any app macOS itself can see.

None of that groundwork is re-explained here. The original project's README
goes into real depth on how each piece works and why — window mechanics,
click-through hit-testing, the Now Playing helper, timer discipline that
keeps the app at 0% CPU at rest, and more. **[Read it at the source](https://github.com/akalikbergenov/cyclop)**
if you want the full picture; it's a genuinely well-documented codebase.

The MIT license lets this fork rename, modify, and redistribute freely, and
that's exactly what happened here — the code was renamed throughout, the app
and status bar icons are custom, and the sections below cover what was added
on top. The original license notice and copyright are kept in [`LICENSE`](LICENSE),
as MIT requires.

## What's added here

| Tab | What it does |
|---|---|
| **RU/EN layout switcher** | Type a word in the wrong keyboard layout and it's corrected in place — backspaced, retyped in the right alphabet, layout switched — the moment the word ends, using the system spell checker rather than a guess. Also fixes skipped **ё** in common words, inserts a comma before "который"/"но"/"а" when one is missing, and has a small allowlist for tech abbreviations (`js`, `css`, `html`, ...) that aren't real dictionary words. An optional same-language spelling autocorrect sits alongside it, off by default. Both toggle independently from the menu bar icon, along with an editable exceptions list for words that should never be touched |
| **Voice input** | Hold **right Option**, speak, let go — the transcript types itself into whatever field is focused. Runs entirely on-device via Apple's Speech framework; no audio ever leaves the Mac. The language follows the active keyboard layout (Russian layout dictates Russian, Latin dictates English), punctuation is added automatically, and long dictation with pauses is inserted whole, not just its tail. The notch peeks out with a live waveform while the key is held. Toggles from the menu bar icon |
| **System** | CPU (user/system/idle) and memory usage, each with the top 5 processes, plus a memory-pressure indicator matching Activity Monitor's own gauge |
| **Network** | Upload/download throughput and the top apps actually using it, read the same way Activity Monitor's Network tab does |
| **Power** | The Mac's own battery, and connected Bluetooth accessories (headphones, mice, keyboards) with their battery level where the hardware reports one |
| **Reminders** | What's due, from one list, several, or all of them — pick which in the tab itself. A click marks something done |
| **Quick Actions** | Runs any of your macOS Shortcuts from the panel — pick which ones show up, run them with a click |

All of the above respects the existing **Hide Contents** privacy mode — each
new tab can be covered individually, same as Clipboard, Snippets, Calendar
and Notes already were.

### On the RU/EN switcher

There's no public API for "is this word in the wrong keyboard layout" — this
uses the same trick a layout is built on: both layouts share physical key
positions, so a word typed in the wrong one can be re-interpreted through the
other layout's table and checked against the system dictionary. If the word
as typed isn't a real word in the active language but the re-interpreted
version is a real word in the other one, it gets corrected. Requires
**Accessibility** and **Input Monitoring** — the two permissions a global
keyboard correction fundamentally needs.

### On voice dictation

Recognition is strictly local: `SFSpeechRecognizer` with
`requiresOnDeviceRecognition`, so nothing is sent anywhere — and if the
active locale can't be recognized on-device, dictation refuses to run rather
than falling back to Apple's servers. The locale is picked from the keyboard
layout in use at the moment the key goes down, so bilingual dictation needs
no switching of any kind. Only the **right** Option key acts as the trigger —
the left one keeps its normal life. Requires **Microphone** and **Speech
Recognition**, both asked lazily on the first key press.

### On Bluetooth accessory battery

Apple has no public API for a paired accessory's battery percentage.
`IOBluetoothDevice` carries a handful of undocumented selectors
(`batteryPercentSingle`, `headsetBattery`, and others) that Apple's own
Bluetooth menu reads internally — this app calls them the same way, but
checks each selector's actual Objective-C type encoding before calling it
rather than assuming one, since calling a scalar-returning method as if it
returned an object is how that kind of shortcut crashes a process. Requires
**Bluetooth** permission.

## Installation

Open the `.dmg` and drag the app into Applications. The first launch will
say the app can't be verified — expected, since this build is ad-hoc signed
without a paid Apple Developer ID. **System Settings → Privacy & Security**
will have an **"Open Anyway"** button waiting near the bottom after the
first attempt.

macOS will then ask, one at a time and only when each feature is first
used, for: **Accessibility** and **Input Monitoring** (the RU/EN switcher),
**Microphone** and **Speech Recognition** (voice dictation), **Bluetooth**
(accessory battery), **Reminders**, and **Calendar**. None of these are
requested at launch — only on the button press or the tab that needs them.

Release builds are signed with a stable self-signed certificate, so macOS
keeps recognizing the app across updates — permissions granted once carry
over. Gatekeeper still warns on first install, since a self-signed
certificate is not a Developer ID.

## Building

```bash
git clone https://github.com/trunjeee/notch.git
cd notch
./Scripts/setup-signing.sh   # one-time: create the signing identity
./Scripts/bundle.sh          # swift build + assemble the .app + sign
open "build/Notch by trj.app"
```

```bash
./Scripts/dmg.sh             # the above, plus a .dmg with an /Applications shortcut inside
```

`bundle.sh` signs with the self-signed identity created by
`setup-signing.sh`, so macOS treats every rebuild as the same app and
permission grants survive. Without it the build falls back to ad-hoc
signing — and macOS re-asks for every permission on every build, since an
ad-hoc signature changes each time.

Requires macOS 15+, and a Swift 6 toolchain (Command Line Tools are enough,
the full Xcode isn't needed).

## Support

The app is free. If it's useful to you: **[trj.at/donate](https://trj.at/donate)**

## License

MIT — see [`LICENSE`](LICENSE). Original copyright (c) 2026 akalikbergenov,
additions (c) 2026 the contributors to this fork.
