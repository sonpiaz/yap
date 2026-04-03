import Cocoa
import CoreGraphics

/// Listens for a global modifier key (default: Command) via CGEventTap.
///
/// IMPORTANT: This class is NOT @MainActor. The CGEventTap callback fires on
/// the main run loop but from a C function — we extract raw values there and
/// dispatch to main queue for state changes.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    /// The modifier flag to listen for. Default = Command.
    var targetModifier: CGEventFlags = .maskCommand

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapCheckTimer: Timer?
    private var isKeyDown = false
    private var lastFlags: UInt64 = 0

    private init() {}

    // MARK: - Setup / Teardown

    func start() {
        stop() // clean any existing tap

        guard CGPreflightListenEventAccess() else {
            NSLog("[Yap] Input Monitoring permission not granted")
            return
        }

        let mask: CGEventMask = 1 << CGEventType.flagsChanged.rawValue

        // C callback — no captures, no Swift closures
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                NSLog("[Yap] CGEventTap was disabled, re-enabling")
                if let tap = mgr.eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }

            let rawFlags = event.flags.rawValue
            mgr.handleFlagsChanged(rawFlags)
            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("[Yap] Failed to create CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Yap] CGEventTap started (listening for modifier 0x%llx)", targetModifier.rawValue)

        // Periodic check: re-enable tap if macOS disabled it (Wispr Flow bug)
        DispatchQueue.main.async {
            self.tapCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                guard let self, let tap = self.eventTap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) {
                    NSLog("[Yap] Re-enabling disabled CGEventTap")
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }
    }

    func stop() {
        tapCheckTimer?.invalidate()
        tapCheckTimer = nil
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isKeyDown = false
        lastFlags = 0
    }

    // MARK: - Flag Handling

    /// Called from the CGEventTap callback (on the main run loop thread).
    /// Extracts whether the target modifier is pressed/released.
    private func handleFlagsChanged(_ rawFlags: UInt64) {
        let targetRaw = targetModifier.rawValue
        let wasDown = (lastFlags & targetRaw) != 0
        let isDown = (rawFlags & targetRaw) != 0
        lastFlags = rawFlags

        if isDown && !wasDown && !isKeyDown {
            // Only fire if ONLY our target modifier is pressed (no other modifiers)
            let otherModifiers: UInt64 = (
                CGEventFlags.maskCommand.rawValue |
                CGEventFlags.maskAlternate.rawValue |
                CGEventFlags.maskControl.rawValue |
                CGEventFlags.maskShift.rawValue
            ) & ~targetRaw
            let hasOtherModifiers = (rawFlags & otherModifiers) != 0
            guard !hasOtherModifiers else { return }

            isKeyDown = true
            NSLog("[Yap] Hotkey DOWN")
            DispatchQueue.main.async { self.onKeyDown?() }
        } else if !isDown && wasDown && isKeyDown {
            isKeyDown = false
            NSLog("[Yap] Hotkey UP")
            DispatchQueue.main.async { self.onKeyUp?() }
        }
    }
}
