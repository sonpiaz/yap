import Cocoa
import CoreGraphics

/// Listens for a global modifier key (default: Command) via CGEventTap.
///
/// To avoid conflict with Cmd+C/V/Z shortcuts, we use a delayed-activation
/// strategy: when Command is pressed alone, we wait a short grace period.
/// If any other key is pressed during that window, we cancel.
/// If Command is still held after the grace period with no other keys → activate.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onKeyDown: (() -> Void)?
    var onKeyUp: (() -> Void)?

    /// The modifier flag to listen for. Default = Command.
    var targetModifier: CGEventFlags = .maskCommand

    /// Grace period to distinguish solo-Command from Cmd+C etc.
    private let activationDelay: TimeInterval = 0.20

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapCheckTimer: Timer?

    private var isModifierDown = false   // physical state: modifier is held
    private var isActivated = false      // logical state: recording triggered
    private var activationWorkItem: DispatchWorkItem?
    private var otherKeyPressed = false  // true if a non-modifier key was pressed during hold

    private init() {}

    // MARK: - Setup / Teardown

    func start() {
        stop()

        guard CGPreflightListenEventAccess() else {
            NSLog("[Yap] Input Monitoring permission not granted")
            return
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                NSLog("[Yap] CGEventTap was disabled, re-enabling")
                if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }

            if type == .keyDown {
                mgr.handleKeyDown()
            } else if type == .flagsChanged {
                mgr.handleFlagsChanged(event.flags.rawValue)
            }
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
        NSLog("[Yap] CGEventTap started (modifier 0x%llx, delay %.0fms)", targetModifier.rawValue, activationDelay * 1000)

        // Re-enable tap if macOS disables it
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
        activationWorkItem?.cancel()
        activationWorkItem = nil
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        isModifierDown = false
        isActivated = false
    }

    // MARK: - Event Handling

    /// A non-modifier key was pressed (C, V, Z, etc.) while modifier is held → it's a shortcut.
    private func handleKeyDown() {
        if isModifierDown && !isActivated {
            // Cancel the pending activation — this is Cmd+C, Cmd+V, etc.
            otherKeyPressed = true
            activationWorkItem?.cancel()
            activationWorkItem = nil
        }
    }

    private func handleFlagsChanged(_ rawFlags: UInt64) {
        let targetRaw = targetModifier.rawValue
        let isDown = (rawFlags & targetRaw) != 0

        // Check no other modifiers are pressed
        let allModifiers: UInt64 =
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskShift.rawValue
        let otherModifiers = (rawFlags & allModifiers) & ~targetRaw
        let hasOtherModifiers = otherModifiers != 0

        if isDown && !isModifierDown && !hasOtherModifiers {
            // Modifier pressed — start grace period
            isModifierDown = true
            otherKeyPressed = false
            activationWorkItem?.cancel()

            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isModifierDown, !self.otherKeyPressed else { return }
                // Grace period passed, no other key was pressed → activate!
                self.isActivated = true
                NSLog("[Yap] Hotkey ACTIVATED (solo hold confirmed)")
                self.onKeyDown?()
            }
            activationWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay, execute: work)

        } else if !isDown && isModifierDown {
            // Modifier released
            isModifierDown = false
            activationWorkItem?.cancel()
            activationWorkItem = nil

            if isActivated {
                isActivated = false
                NSLog("[Yap] Hotkey RELEASED")
                DispatchQueue.main.async { self.onKeyUp?() }
            }
            otherKeyPressed = false
        }
    }
}
