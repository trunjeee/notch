#!/usr/bin/env swift
// Standalone diagnostic for the RU/EN switcher's event tap.
// Run directly: swift Scripts/switcher_diag.swift
// It will print exactly what's failing — permission, tap creation, or capture.

import AppKit
import ApplicationServices
import Carbon.HIToolbox

print("1) AXIsProcessTrusted() before prompt: \(AXIsProcessTrusted())")

let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
_ = AXIsProcessTrustedWithOptions(options as CFDictionary)
print("   (a system prompt may have just appeared — check it, then re-run this script)")

Thread.sleep(forTimeInterval: 0.3)
print("2) AXIsProcessTrusted() after prompt attempt: \(AXIsProcessTrusted())")

let mask = (1 << CGEventType.keyDown.rawValue)
guard let tap = CGEvent.tapCreate(
    tap: .cgSessionEventTap,
    place: .headInsertEventTap,
    options: .listenOnly,
    eventsOfInterest: CGEventMask(mask),
    callback: { _, type, event, _ in
        if type == .keyDown {
            let keycode = event.getIntegerValueField(.keyboardEventKeycode)
            if let nsEvent = NSEvent(cgEvent: event), let chars = nsEvent.characters {
                print("   keyDown: keycode=\(keycode) chars='\(chars)'")
            }
        }
        return Unmanaged.passRetained(event)
    },
    userInfo: nil
) else {
    print("3) FAILED to create event tap.")
    print("   -> Almost certainly missing Input Monitoring permission for this process.")
    print("   -> Go to System Settings > Privacy & Security > Input Monitoring")
    print("   -> and Accessibility, add whatever binary this printed as trusted, or")
    print("   -> just re-run this script after granting.")
    exit(1)
}

print("3) Event tap created successfully.")
let runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)

print("4) Listening for 10 seconds — type something now (any window).")
CFRunLoopRunInMode(.defaultMode, 10, false)
print("5) Done. If you saw 'keyDown: ...' lines above, capture works fine —")
print("   the problem is somewhere in the app's own correction logic, not permissions.")
print("   If you saw NO keyDown lines, Input Monitoring is not actually granted.")
