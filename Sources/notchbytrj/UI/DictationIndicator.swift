import AppKit

/// The small floating dot shown while dictation is recording, parked next
/// to the text caret — the eyes are already there. Falls back to the mouse
/// pointer when the caret can't be located (fields without Accessibility
/// text support). Purely visual: takes no clicks and no keyboard focus.
@MainActor
final class DictationIndicator {

    private var panel: NSPanel?
    private var dot: NSView?

    func show() {
        if panel == nil { build() }
        positionNearCaret()
        panel?.orderFrontRegardless()
    }

    /// Live microphone level, 0…1. The dot breathes with the voice — the
    /// one glance that answers "is it hearing me?" without opening anything.
    func update(level: Float) {
        let clamped = CGFloat(max(0, min(1, level)))
        let scale = 0.75 + 0.5 * clamped
        dot?.layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        dot?.layer?.opacity = Float(0.65 + 0.35 * clamped)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func build() {
        let size = NSSize(width: 30, height: 30)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor
        content.layer?.cornerRadius = size.height / 2

        let dotSize: CGFloat = 12
        let dot = NSView(frame: NSRect(
            x: (size.width - dotSize) / 2,
            y: (size.height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        ))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = dotSize / 2

        content.addSubview(dot)
        panel.contentView = content

        self.panel = panel
        self.dot = dot
    }

    private func positionNearCaret() {
        let offset = NSPoint(x: 16, y: 14)
        if let caret = Self.textCaretLocation() {
            panel?.setFrameOrigin(NSPoint(x: caret.x + offset.x, y: caret.y + offset.y))
        } else {
            let mouse = NSEvent.mouseLocation
            panel?.setFrameOrigin(NSPoint(x: mouse.x + offset.x, y: mouse.y + offset.y))
        }
    }

    /// Screen coordinates of the text caret in the focused field, read
    /// through the Accessibility API. AX reports a top-left-origin global
    /// frame; AppKit window origins are bottom-left, so y is flipped
    /// against the primary screen.
    private static func textCaretLocation() -> NSPoint? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: AnyObject?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedObject
        ) == .success else { return nil }
        let focused = focusedObject as! AXUIElement

        var rangeObject: AnyObject?
        guard AXUIElementCopyAttributeValue(
            focused,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeObject
        ) == .success, let rangeObject else { return nil }

        var boundsObject: AnyObject?
        guard AXUIElementCopyParameterizedAttributeValue(
            focused,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeObject,
            &boundsObject
        ) == .success else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsObject as! AXValue, .cgRect, &rect) else { return nil }

        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return NSPoint(x: rect.maxX, y: mainHeight - rect.maxY)
    }
}
