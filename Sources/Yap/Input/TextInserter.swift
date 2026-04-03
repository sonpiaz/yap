import AppKit
import ApplicationServices

/// Inserts transcribed text into the frontmost app.
/// Strategy: try Accessibility API first, fallback to clipboard + Cmd+V.
enum TextInserter {

    static func insert(_ text: String) {
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
        guard let app = NSWorkspace.shared.frontmostApplication else { return false }
        let element = AXUIElementCreateApplication(app.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success else {
            return false
        }

        let focused = focusedRef as! AXUIElement
        return AXUIElementSetAttributeValue(focused, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
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
        down?.post(tap: .cgAnnotatedSessionEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
