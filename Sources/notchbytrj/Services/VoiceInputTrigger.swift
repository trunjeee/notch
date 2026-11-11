import AppKit
import Carbon.HIToolbox

/// Watches for the right Option key specifically: press starts dictation,
/// release finishes it. Left Option is a different keycode and never
/// matches; a plain Option press types nothing, so the listen-only tap has
/// nothing to swallow.
final class VoiceInputTrigger {

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    var isEnabled = true
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    func start() {
        let mask = 1 << CGEventType.flagsChanged.rawValue
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passRetained(event) }
                let trigger = Unmanaged<VoiceInputTrigger>.fromOpaque(refcon).takeUnretainedValue()
                trigger.handle(event: event, type: type)
                return Unmanaged.passRetained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("notchbytrj-dictation: failed to create event tap — check Accessibility/Input Monitoring permissions")
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("notchbytrj-dictation: event tap started, trusted=\(AXIsProcessTrusted())")
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        eventTap = nil
        runLoopSource = nil
        isDown = false
    }

    private func handle(event: CGEvent, type: CGEventType) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard isEnabled, type == .flagsChanged else { return }

        // kVK_RightOption = 0x3D. Left Option (0x3A) is deliberately ignored:
        // it keeps doing its day job in shortcuts and special characters.
        guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_RightOption) else { return }

        let down = event.flags.contains(.maskAlternate)
        if down, !isDown {
            isDown = true
            NSLog("notchbytrj-dictation: right Option down")
            onPress?()
        } else if !down, isDown {
            isDown = false
            NSLog("notchbytrj-dictation: right Option up")
            onRelease?()
        }
        // Known gap: releasing right Option while left Option is still held
        // keeps .maskAlternate set, so that one release goes unseen. Rare
        // enough in real typing to live with.
    }
}
