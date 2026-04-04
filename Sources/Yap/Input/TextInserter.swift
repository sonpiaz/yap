import AppKit
import ApplicationServices

/// Inserts transcribed text into the frontmost app.
/// Strategy: restore focus → try AX insertion → fallback to clipboard + Cmd+V.
enum TextInserter {

    /// The app that was focused when recording started.
    /// Set this before transcription so we can restore focus if needed.
    static var targetApp: NSRunningApplication?

    /// Async insert that properly waits for focus restoration without blocking main thread.
    static func insert(_ text: String) async {
        // Restore focus to the app the user was dictating into
        if let target = targetApp, target.bundleIdentifier != Bundle.main.bundleIdentifier {
            target.activate()

            // Poll until target app is actually frontmost (non-blocking)
            for _ in 0..<20 { // max ~400ms
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                    // One more yield to let the target app's run loop process the activation
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    break
                }
            }

            let actual = NSWorkspace.shared.frontmostApplication
            NSLog("[Yap] Focus restore: target=%@ actual=%@ match=%d",
                  target.bundleIdentifier ?? "nil",
                  actual?.bundleIdentifier ?? "nil",
                  (target.processIdentifier == actual?.processIdentifier) ? 1 : 0)
        }

        // Try AX direct insertion (no clipboard pollution)
        if AXIsProcessTrusted(), tryAXInsertion(text) {
            NSLog("[Yap] Text inserted via Accessibility")
            return
        }

        // Fallback: clipboard + Cmd+V
        pasteViaClipboard(text)
        NSLog("[Yap] Text inserted via clipboard paste")
    }

    // MARK: - AX Direct Insert

    private static func tryAXInsertion(_ text: String) -> Bool {
        guard let app = targetApp ?? NSWorkspace.shared.frontmostApplication else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success else {
            NSLog("[Yap] AX: no focused element in %@", app.bundleIdentifier ?? "unknown")
            return false
        }

        let focused = focusedRef as! AXUIElement

        // Try 1: Set selected text (works in native text fields)
        if AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success {
            return true
        }

        // Try 2: Get current value + selection range, insert at cursor position
        var valueRef: CFTypeRef?
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(focused, kAXValueAttribute as CFString, &valueRef) == .success,
           AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
           let currentValue = valueRef as? String {

            var range = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                var newValue = currentValue
                let startIndex = newValue.index(newValue.startIndex, offsetBy: min(range.location, currentValue.count))
                let endIndex = newValue.index(startIndex, offsetBy: min(range.length, currentValue.count - range.location))
                newValue.replaceSubrange(startIndex..<endIndex, with: text)

                if AXUIElementSetAttributeValue(focused, kAXValueAttribute as CFString, newValue as CFTypeRef) == .success {
                    // Move cursor to end of inserted text
                    let newPos = range.location + text.count
                    var newRange = CFRangeMake(newPos, 0)
                    if let axRange = AXValueCreate(.cfRange, &newRange) {
                        AXUIElementSetAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, axRange)
                    }
                    return true
                }
            }
        }

        NSLog("[Yap] AX: insertion failed, falling back to clipboard")
        return false
    }

    // MARK: - Clipboard + Cmd+V

    private static func pasteViaClipboard(_ text: String) {
        let pb = NSPasteboard.general
        let old = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        simulateCmdV()

        // Restore old clipboard after 500ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let old {
                pb.clearContents()
                pb.setString(old, forType: .string)
            }
        }
    }

    private static func simulateCmdV() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        // key 0x09 = "V"
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cghidEventTap)
    }
}
