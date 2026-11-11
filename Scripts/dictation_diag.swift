#!/usr/bin/env swift
// Standalone diagnostic for voice dictation's right-Option trigger.
// Run directly: swift Scripts/dictation_diag.swift
// It prints whether the event tap can be created at all (permissions) and
// what keycode each Option press actually reports — so "I hold the key and
// nothing happens" becomes a named failure.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

print("1) AXIsProcessTrusted(): \(AXIsProcessTrusted())")
print("   (this process is whatever ran the script — usually Terminal —")
print("   and needs its OWN Accessibility + Input Monitoring grants)")

let mask = 1 << CGEventType.flagsChanged.rawValue
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(mask),
    callback: { _, type, event, _ in
        guard type == .flagsChanged else { return Unmanaged.passRetained(event) }
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let altDown = event.flags.contains(.maskAlternate)
        // 0x3A = left Option, 0x3D = right Option
        if keycode == Int64(kVK_RightOption) || keycode == Int64(kVK_LeftOption) {
            let which = (keycode == Int64(kVK_RightOption)) ? "RIGHT" : "left"
            print("   Option pressed: \(which), alt flag down = \(altDown), keycode = \(keycode)")
        }
        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    print("2) FAILED to create event tap — Input Monitoring is missing for this process.")
    print("   System Settings > Privacy & Security > Input Monitoring (and Accessibility).")
    exit(1)
}

print("2) Event tap created.")
let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("3) Listening for 15 seconds — press and release RIGHT Option a few times.")
print("   Expected lines: 'Option pressed: RIGHT, alt flag down = true/false, keycode = 61'.")
print("   If nothing prints while you press it, the key never reaches an event")
print("   tap on this machine (remapper, or the press is consumed elsewhere).")
CFRunLoopRunInMode(.defaultMode, 15, false)
print("4) Done.")
