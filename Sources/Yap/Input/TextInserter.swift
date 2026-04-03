import AppKit
import ApplicationServices

enum OutputMode: String, CaseIterable, Identifiable {
    case pasteOnly = "Paste Only"
    case pasteAndSubmit = "Paste + Enter"
    case copyOnly = "Copy Only"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .pasteOnly:
            return "Paste transcription into the active app"
        case .pasteAndSubmit:
            return "Paste, then press Enter to submit"
        case .copyOnly:
            return "Copy transcription to the clipboard only"
        }
    }
}

enum TextInserter {

    static func insert(_ text: String) {
        let mode = currentOutputMode()
        let shouldPressEnter = (mode == .pasteAndSubmit)

        switch mode {
        case .copyOnly:
            copyToClipboard(text)

        case .pasteOnly, .pasteAndSubmit:
            // Try AX direct insert first (no clipboard pollution)
            if AXIsProcessTrusted(), tryAXInsertion(text) {
                if shouldPressEnter {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        simulateEnter()
                    }
                }
                return
            }
            // Fallback: clipboard + Cmd+V
            pasteViaClipboard(text, pressEnterAfterPaste: shouldPressEnter)
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

    private static func pasteViaClipboard(_ text: String, pressEnterAfterPaste: Bool) {
        let pasteboard = NSPasteboard.general
        let oldContents = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        simulateCmdV()

        if pressEnterAfterPaste {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                simulateEnter()
            }
        }

        // Restore old clipboard after 400ms
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if let old = oldContents {
                pasteboard.clearContents()
                pasteboard.setString(old, forType: .string)
            }
        }
    }

    private static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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

    private static func simulateEnter() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }

        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: true)
        down?.post(tap: .cgAnnotatedSessionEventTap)

        let up = CGEvent(keyboardEventSource: src, virtualKey: 0x24, keyDown: false)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    private static func currentOutputMode() -> OutputMode {
        if let raw = UserDefaults.standard.string(forKey: "outputMode"),
           let mode = OutputMode(rawValue: raw) {
            return mode
        }

        let legacyAutoPaste = UserDefaults.standard.bool(forKey: "autoPaste")
        return legacyAutoPaste ? .pasteOnly : .copyOnly
    }

    // MARK: - Permission

    @discardableResult
    static func requestAccessibilityIfNeeded() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
