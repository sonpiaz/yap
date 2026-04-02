import Cocoa
import Carbon
import Combine

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHotkeyDown = false
    private var recordingStartTime: Date?

    // Default: Right Option key for push-to-talk
    private let triggerKeyCode: CGKeyCode = 61  // Right Option
    private let minimumRecordingDuration: TimeInterval = 0.3  // Ignore accidental taps

    private init() {}

    func setup() {
        requestAccessibilityPermissions()
        installEventTap()
    }

    private func requestAccessibilityPermissions() {
        let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private func installEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: { _, type, event, _ -> Unmanaged<CGEvent>? in
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

        print("[Yap] Event tap installed — hold Right Option to record")
    }

    private func handleEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        // Handle Right Option key
        if keyCode == triggerKeyCode {
            let flags = event.flags

            if flags.contains(.maskAlternate) && !isHotkeyDown {
                // Key pressed down — start recording
                isHotkeyDown = true
                recordingStartTime = Date()
                DispatchQueue.main.async {
                    PipelineController.shared.startRecording()
                }
                return nil  // Consume the event

            } else if !flags.contains(.maskAlternate) && isHotkeyDown {
                // Key released — stop recording
                isHotkeyDown = false
                let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0

                if duration >= minimumRecordingDuration {
                    DispatchQueue.main.async {
                        PipelineController.shared.stopAndTranscribe()
                    }
                } else {
                    // Too short — cancel
                    DispatchQueue.main.async {
                        PipelineController.shared.cancelRecording()
                    }
                }
                recordingStartTime = nil
                return nil  // Consume the event
            }
        }

        return Unmanaged.passRetained(event)
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
