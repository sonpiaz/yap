import Cocoa
import Combine
import ApplicationServices
import os.log

private let hmLogger = Logger(subsystem: "com.sonpiaz.yap", category: "HotkeyManager")

enum RecordingMode: String, CaseIterable, Identifiable {
    case holdToTalk = "Hold to Talk"
    case toggle = "Toggle"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .holdToTalk:
            return "Hold the hotkey to record, release to transcribe"
        case .toggle:
            return "Press once to start recording, press again to stop and transcribe"
        }
    }
}

@MainActor
class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    private var isHotkeyDown = false
    private var recordingStartTime: Date?
    private let minimumRecordingDuration: TimeInterval = 0.3
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var currentFlags: NSEvent.ModifierFlags = []

    private var recordingMode: RecordingMode {
        let raw = UserDefaults.standard.string(forKey: "recordingMode") ?? RecordingMode.holdToTalk.rawValue
        return RecordingMode(rawValue: raw) ?? .holdToTalk
    }

    private var trigger: PushToTalkTrigger {
        PushToTalkTrigger.loadFromDefaults()
    }

    private init() {
        setupHandlers()
    }

    func setup() {
        teardownMonitors()
        setupHandlers()
    }

    private func setupHandlers() {
        let hasPerm = CGPreflightListenEventAccess()
        NSLog("[Yap] setupHandlers called, CGPreflightListenEventAccess=%d", hasPerm ? 1 : 0)
        guard PermissionManager.shared.inputMonitoringStatus == .granted || hasPerm else {
            NSLog("[Yap] Input Monitoring not granted")
            return
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handleFromTap(cgEvent: event, type: type)
            return Unmanaged.passRetained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: refcon
        ) else {
            print("[Yap] Failed to create CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Yap] CGEventTap created and enabled successfully")
    }

    nonisolated func handleFromTap(cgEvent: CGEvent, type: CGEventType) {
        NSLog("[Yap] event received type: %u, flags raw: %llu", type.rawValue, cgEvent.flags.rawValue)
        let flagsRaw = cgEvent.flags.rawValue
        let keycode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
        let autorepeat = cgEvent.getIntegerValueField(.keyboardEventAutorepeat)
        DispatchQueue.main.async {
            self.dispatchEvent(type: type, flagsRaw: flagsRaw, keycode: keycode, autorepeat: autorepeat)
        }
    }

    private func dispatchEvent(type: CGEventType, flagsRaw: UInt64, keycode: Int64, autorepeat: Int64) {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(flagsRaw: flagsRaw)
        case .keyDown:
            handleKeyDownEvent(flagsRaw: flagsRaw, keycode: keycode, autorepeat: autorepeat)
        case .keyUp:
            handleKeyUpEvent(flagsRaw: flagsRaw, keycode: keycode)
        default:
            break
        }
    }

    private func handleFlagsChanged(flagsRaw: UInt64) {
        let newFlags = normalizedFlags(NSEvent.ModifierFlags(rawValue: UInt(flagsRaw)))
        let oldFlags = currentFlags
        currentFlags = newFlags

        guard trigger.kind == .modifier, let modifier = trigger.modifier else { return }
        let targetFlag = modifier.eventFlag

        let wasPressed = oldFlags.contains(targetFlag)
        let isPressed = newFlags.contains(targetFlag)
        let onlyTargetPressed = newFlags == targetFlag
        let targetReleased = wasPressed && !isPressed
        let transitionedAwayFromTargetOnly = wasPressed && oldFlags == targetFlag && newFlags != targetFlag

        if !wasPressed && isPressed && onlyTargetPressed {
            handleKeyDown()
        } else if targetReleased || transitionedAwayFromTargetOnly {
            handleKeyUp()
        }
    }

    private func handleKeyDownEvent(flagsRaw: UInt64, keycode: Int64, autorepeat: Int64) {
        guard trigger.kind == .combo else { return }
        guard matchesCombo(flagsRaw: flagsRaw, keycode: keycode) else { return }
        if autorepeat == 0 {
            handleKeyDown()
        }
    }

    private func handleKeyUpEvent(flagsRaw: UInt64, keycode: Int64) {
        guard trigger.kind == .combo else { return }
        guard let keyCode = trigger.keyCode,
              UInt16(keycode) == keyCode else { return }
        handleKeyUp()
    }

    private func matchesCombo(flagsRaw: UInt64, keycode: Int64) -> Bool {
        guard let keyCode = trigger.keyCode else { return false }
        guard UInt16(keycode) == keyCode else { return false }
        let flags = normalizedFlags(NSEvent.ModifierFlags(rawValue: UInt(flagsRaw)))
        let expected = NSEvent.ModifierFlags(trigger.modifiers.map(\.eventFlag))
        return flags == expected
    }

    private func normalizedFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift, .function])
    }

    private func handleKeyDown() {
        guard !isHotkeyDown else { return }
        isHotkeyDown = true
        NSLog("[Yap] handleKeyDown → startRecording, mode: %@", recordingMode.rawValue)

        switch recordingMode {
        case .holdToTalk:
            recordingStartTime = Date()
            DispatchQueue.main.async {
                PipelineController.shared.startRecording()
            }
        case .toggle:
            DispatchQueue.main.async {
                PipelineController.shared.toggleRecording()
            }
        }
    }

    private func handleKeyUp() {
        guard isHotkeyDown else { return }
        isHotkeyDown = false
        NSLog("[Yap] handleKeyUp → stopRecording")

        guard recordingMode == .holdToTalk else { return }

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

    private func teardownMonitors() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    func cleanup() {
        teardownMonitors()
    }
}

private extension NSEvent.ModifierFlags {
    init(_ values: [NSEvent.ModifierFlags]) {
        self = []
        for value in values {
            insert(value)
        }
    }
}
