import AppKit
import ApplicationServices
import UserNotifications

/// Inserts transcribed text into the frontmost app.
/// Strategy: restore focus → try AX insertion → fallback to clipboard + Cmd+V → ultimate fallback: clipboard + notification.
enum TextInserter {

    /// The app that was focused when recording started.
    /// Set this before transcription so we can restore focus if needed.
    static var targetApp: NSRunningApplication?

    /// Async insert that properly waits for focus restoration without blocking main thread.
    static func insert(_ text: String) async {
        // Check Accessibility permission first
        guard AXIsProcessTrusted() else {
            NSLog("[Yap] ⚠️ Accessibility NOT granted — cannot insert text, copying to clipboard")
            copyToClipboardWithNotification(text, reason: "Grant Accessibility permission in System Settings so Yap can type for you.")
            return
        }

        // Restore focus to the app the user was dictating into
        var focusRestored = false
        if let target = targetApp, target.bundleIdentifier != Bundle.main.bundleIdentifier {
            target.activate()

            // Poll until target app is actually frontmost (non-blocking)
            for _ in 0..<20 { // max ~400ms
                try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier {
                    // One more yield to let the target app's run loop process the activation
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                    focusRestored = true
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
        if tryAXInsertion(text) {
            NSLog("[Yap] ✅ Text inserted via Accessibility")
            return
        }

        // Fallback: clipboard + Cmd+V
        if pasteViaClipboard(text) {
            NSLog("[Yap] ✅ Text inserted via clipboard paste")
            return
        }

        // Ultimate fallback: just copy to clipboard and notify user
        NSLog("[Yap] ⚠️ All insertion methods failed, text copied to clipboard")
        copyToClipboardWithNotification(text, reason: "Auto-paste failed. Text is in your clipboard — press ⌘V to paste.")
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

    /// Returns true if paste was likely successful (CGEvent created OK)
    private static func pasteViaClipboard(_ text: String) -> Bool {
        let pb = NSPasteboard.general
        let old = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)

        let pasted = simulateCmdV()

        if pasted {
            // Restore old clipboard after 500ms
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let old {
                    pb.clearContents()
                    pb.setString(old, forType: .string)
                }
            }
        }

        return pasted
    }

    /// Returns true if CGEvent was successfully created and posted
    private static func simulateCmdV() -> Bool {
        guard let src = CGEventSource(stateID: .hidSystemState) else {
            NSLog("[Yap] CGEventSource creation failed")
            return false
        }
        // key 0x09 = "V"
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true),
              let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false) else {
            NSLog("[Yap] CGEvent creation failed")
            return false
        }

        down.flags = .maskCommand
        down.post(tap: .cghidEventTap)

        up.flags = .maskCommand
        up.post(tap: .cghidEventTap)

        return true
    }

    // MARK: - Ultimate Fallback: Clipboard + Notification

    private static func copyToClipboardWithNotification(_ text: String, reason: String) {
        // Always ensure text is in clipboard
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        // Show macOS notification
        let content = UNMutableNotificationContent()
        content.title = "Yap — Text Ready"
        content.subtitle = reason
        // Show first 100 chars of text in notification body
        content.body = String(text.prefix(100)) + (text.count > 100 ? "…" : "")
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "yap-insertion-fallback-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("[Yap] Notification error: %@", error.localizedDescription)
            }
        }

        // Also update AppState error to show in UI
        Task { @MainActor in
            AppState.shared.error = "⌘V to paste — \(reason)"
        }
    }
}
