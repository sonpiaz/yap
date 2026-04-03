import Cocoa
import Combine
import ApplicationServices

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
        guard PermissionManager.shared.inputMonitoringStatus == .granted || CGPreflightListenEventAccess() else {
            print("[Yap] Input Monitoring not granted")
            return
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue) |
                   (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
            manager.handle(cgEvent: event, type: type)
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
    }

    private func handle(cgEvent: CGEvent, type: CGEventType) {
        switch type {
        case .flagsChanged:
            handleFlagsChanged(cgEvent)
        case .keyDown:
            handleKeyDownEvent(cgEvent)
        case .keyUp:
            handleKeyUpEvent(cgEvent)
        default:
            break
        }
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let newFlags = normalizedFlags(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
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

    private func handleKeyDownEvent(_ event: CGEvent) {
        guard trigger.kind == .combo else { return }
        guard matchesCombo(event) else { return }
        if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
            handleKeyDown()
        }
    }

    private func handleKeyUpEvent(_ event: CGEvent) {
        guard trigger.kind == .combo else { return }
        guard let keyCode = trigger.keyCode,
              UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return }
        handleKeyUp()
    }

    private func matchesCombo(_ event: CGEvent) -> Bool {
        guard let keyCode = trigger.keyCode else { return false }
        guard UInt16(event.getIntegerValueField(.keyboardEventKeycode)) == keyCode else { return false }
        let flags = normalizedFlags(NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)))
        let expected = NSEvent.ModifierFlags(trigger.modifiers.map(\.eventFlag))
        return flags == expected
    }

    private func normalizedFlags(_ flags: NSEvent.ModifierFlags) -> NSEvent.ModifierFlags {
        flags.intersection([.command, .option, .control, .shift, .function])
    }

    private func handleKeyDown() {
        guard !isHotkeyDown else { return }
        isHotkeyDown = true

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
