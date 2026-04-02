import Cocoa
import Carbon
import Combine

enum TriggerKey: String, CaseIterable, Identifiable {
    case rightOption = "Right Option (⌥)"
    case rightCommand = "Right Command (⌘)"
    case leftControl = "Left Control (⌃)"
    case fn = "Fn (Globe)"
    case f5 = "F5"
    case f6 = "F6"

    var id: String { rawValue }

    var keyCode: CGKeyCode {
        switch self {
        case .rightOption: return 61
        case .rightCommand: return 54
        case .leftControl: return 59
        case .fn: return 63
        case .f5: return 96
        case .f6: return 97
        }
    }

    /// Whether this key is a modifier (detected via flagsChanged) or a regular key
    var isModifier: Bool {
        switch self {
        case .rightOption, .rightCommand, .leftControl, .fn: return true
        case .f5, .f6: return false
        }
    }

    /// The CGEventFlags mask to check for modifier keys
    var flagMask: CGEventFlags? {
        switch self {
        case .rightOption: return .maskAlternate
        case .rightCommand: return .maskCommand
        case .leftControl: return .maskControl
        case .fn: return .maskSecondaryFn
        case .f5, .f6: return nil
        }
    }
}

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyDown = false
    private var recordingStartTime: Date?

    @Published var currentKey: TriggerKey {
        didSet {
            UserDefaults.standard.set(currentKey.rawValue, forKey: "triggerKey")
        }
    }

    private let minimumRecordingDuration: TimeInterval = 0.3

    private init() {
        if let saved = UserDefaults.standard.string(forKey: "triggerKey"),
           let key = TriggerKey(rawValue: saved) {
            currentKey = key
        } else {
            currentKey = .rightOption
        }
    }

    func setup() {
        requestAccessibilityPermissions()
        installEventTap()
    }

    func changeKey(_ key: TriggerKey) {
        currentKey = key
        print("[Yap] Hotkey changed to \(key.rawValue)")
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func installEventTap() {
        // Listen to all key events + flags (modifier) changes
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // .defaultTap lets us consume events
            eventsOfInterest: eventMask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
                // Re-enable tap if macOS disables it (happens under heavy load)
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = HotkeyManager.shared.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passRetained(event)
                }
                return HotkeyManager.shared.handleEvent(type: type, event: event)
            },
            userInfo: nil
        ) else {
            print("[Yap] Failed to create event tap — need Accessibility permission")
            return
        }

        self.eventTap = tap
        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = runLoopSource
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        print("[Yap] Event tap installed — hold \(currentKey.rawValue) to record")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let key = currentKey

        // Debug logging (remove later)
        if type == .flagsChanged {
            let flags = event.flags
            print("[Yap:debug] flagsChanged keyCode=\(keyCode) flags=\(flags.rawValue)")
        } else if type == .keyDown || type == .keyUp {
            print("[Yap:debug] \(type == .keyDown ? "keyDown" : "keyUp") keyCode=\(keyCode)")
        }

        if key.isModifier {
            return handleModifierKey(keyCode: keyCode, event: event, key: key)
        } else {
            return handleRegularKey(keyCode: keyCode, type: type, event: event, key: key)
        }
    }

    // MARK: - Modifier keys (Option, Command, Control, Fn)

    private func handleModifierKey(keyCode: CGKeyCode, event: CGEvent, key: TriggerKey) -> Unmanaged<CGEvent>? {
        guard keyCode == key.keyCode, let mask = key.flagMask else {
            return Unmanaged.passRetained(event)
        }

        let flags = event.flags

        if flags.contains(mask) && !isHotkeyDown {
            isHotkeyDown = true
            recordingStartTime = Date()
            DispatchQueue.main.async {
                PipelineController.shared.startRecording()
            }
            return nil
        } else if !flags.contains(mask) && isHotkeyDown {
            isHotkeyDown = false
            finishRecording()
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    // MARK: - Regular keys (F5, F6, etc.)

    private func handleRegularKey(keyCode: CGKeyCode, type: CGEventType, event: CGEvent, key: TriggerKey) -> Unmanaged<CGEvent>? {
        guard keyCode == key.keyCode else {
            return Unmanaged.passRetained(event)
        }

        if type == .keyDown && !isHotkeyDown {
            isHotkeyDown = true
            recordingStartTime = Date()
            DispatchQueue.main.async {
                PipelineController.shared.startRecording()
            }
            return nil
        } else if type == .keyUp && isHotkeyDown {
            isHotkeyDown = false
            finishRecording()
            return nil
        }

        return Unmanaged.passRetained(event)
    }

    private func finishRecording() {
        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil

        if duration >= minimumRecordingDuration {
            DispatchQueue.main.async {
                PipelineController.shared.stopAndTranscribe()
            }
        } else {
            DispatchQueue.main.async {
                PipelineController.shared.cancelRecording()
            }
        }
    }

    func cleanup() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
    }
}
