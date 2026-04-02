import AppKit
import ApplicationServices

enum TextInserter {

    static func insert(_ text: String) {
        let autoPaste = UserDefaults.standard.bool(forKey: "autoPaste")

        if autoPaste {
            // Try AX direct insert first (no clipboard pollution)
            if AXIsProcessTrusted(), tryAXInsertion(text) {
                return
            }
            // Fallback: clipboard + Cmd+V
            pasteViaClipboard(text)
        } else {
            // Just copy to clipboard
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        }
    }

    // MARK: - AX Direct Insert

    private static func tryAXInsertion(_ text: String) -> Bool {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else { return false }
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        ) == .success else { return false }

        let focused = focusedRef as! AXUIElement

        let result = AXUIElementSetAttributeValue(
            focused,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    // MARK: - Clipboard + Cmd+V

    private static func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulateCmdV()

        // Restore old clipboard after 400ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    private static func simulateCmdV() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }

        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        down?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        up?.flags = .maskCommand
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: - Permission

    @discardableResult
    static func requestAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
