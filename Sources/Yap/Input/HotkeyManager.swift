import Cocoa
import CoreGraphics

/// Listens for a modifier-only hold (default: Command) via an ACTIVE CGEventTap.
///
/// Architecture (reverse-engineered from Wispr Flow):
/// When ⌘ is pressed, we INTERCEPT all subsequent key events and buffer them.
/// After a grace period:
///   - If ⌘ was held alone → start recording (discard buffered events)
///   - If another key was pressed (Cmd+C/V) → FLUSH buffer (replay events to OS)
///   - If ⌘ was released quickly → FLUSH buffer (it was just a tap)
///
/// This prevents Cmd+shortcuts from being "eaten" while still detecting solo-holds.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onModifierDown: (() -> Void)?   // fires immediately when modifier pressed
    var onKeyDown: (() -> Void)?         // fires after grace period (confirmed solo hold)
    var onKeyUp: (() -> Void)?
    var onCancelled: (() -> Void)?

    var targetModifier: CGEventFlags = .maskCommand

    /// Grace period to distinguish solo-Command from Cmd+C etc.
    private let activationDelay: TimeInterval = 0.15

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapCheckTimer: Timer?

    private var isModifierDown = false
    private var isActivated = false
    private var activationWorkItem: DispatchWorkItem?

    /// Buffered key events during grace period — replayed if it's a shortcut
    private var eventBuffer: [(event: CGEvent, proxy: CGEventTapProxy)] = []
    private var isBuffering = false

    private init() {}

    // MARK: - Setup / Teardown

    func start() {
        stop()

        guard CGPreflightListenEventAccess() else {
            NSLog("[Yap] Input Monitoring permission not granted")
            return
        }

        // Event types to intercept
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                NSLog("[Yap] CGEventTap was disabled, re-enabling")
                if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }

            if type == .flagsChanged {
                return mgr.handleFlagsChanged(event: event, proxy: proxy)
            }

            if type == .keyDown || type == .keyUp {
                return mgr.handleKeyEvent(event: event, proxy: proxy, isDown: type == .keyDown)
            }

            return Unmanaged.passUnretained(event)
        }

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // ACTIVE tap (not .listenOnly) — we need to intercept events
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,        // ← ACTIVE tap, can block/modify events
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            NSLog("[Yap] Failed to create CGEventTap — trying listenOnly fallback")
            // Fallback to listenOnly if active tap fails
            startListenOnly()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Yap] CGEventTap started (ACTIVE, modifier 0x%llx, delay %.0fms)",
              targetModifier.rawValue, activationDelay * 1000)

        // Re-enable tap if macOS disables it
        DispatchQueue.main.async {
            self.tapCheckTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
                guard let self, let tap = self.eventTap else { return }
                if !CGEvent.tapIsEnabled(tap: tap) {
                    NSLog("[Yap] CGEventTap disabled! Re-enabling...")
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
            }
        }
    }

    /// Fallback for when active tap can't be created
    private func startListenOnly() {
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
            let mgr = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = mgr.eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return Unmanaged.passUnretained(event)
            }

            if type == .flagsChanged {
                _ = mgr.handleFlagsChanged(event: event, proxy: proxy)
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
            NSLog("[Yap] Failed to create even listenOnly CGEventTap")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        NSLog("[Yap] CGEventTap started (listenOnly fallback)")
    }

    func stop() {
        tapCheckTimer?.invalidate()
        tapCheckTimer = nil
        activationWorkItem?.cancel()
        activationWorkItem = nil
        flushBuffer()
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
        isBuffering = false
    }

    // MARK: - Event Handling

    /// Handle modifier key changes (⌘ down/up)
    private func handleFlagsChanged(event: CGEvent, proxy: CGEventTapProxy) -> Unmanaged<CGEvent>? {
        let rawFlags = event.flags.rawValue
        let targetRaw = targetModifier.rawValue
        let isDown = (rawFlags & targetRaw) != 0

        // Check no other modifiers
        let allModifiers: UInt64 =
            CGEventFlags.maskCommand.rawValue |
            CGEventFlags.maskAlternate.rawValue |
            CGEventFlags.maskControl.rawValue |
            CGEventFlags.maskShift.rawValue
        let otherModifiers = (rawFlags & allModifiers) & ~targetRaw
        let hasOtherModifiers = otherModifiers != 0

        if isDown && !isModifierDown && !hasOtherModifiers {
            // ⌘ pressed — start intercepting
            isModifierDown = true
            isBuffering = true
            eventBuffer.removeAll()
            activationWorkItem?.cancel()

            NSLog("[Yap] ⌘ down — buffering events")

            // Start pre-recording immediately (mic warmup)
            DispatchQueue.main.async { self.onModifierDown?() }

            // Schedule activation after grace period
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isModifierDown else { return }

                if self.eventBuffer.isEmpty {
                    // No other keys pressed — clean solo hold → activate!
                    self.isActivated = true
                    self.isBuffering = false
                    NSLog("[Yap] ⌘ ACTIVATED — solo hold confirmed")
                    self.onKeyDown?()
                } else {
                    // Keys were pressed during grace period → it's a shortcut
                    // Flush buffered events back to the OS
                    NSLog("[Yap] ⌘ grace period ended but %d keys buffered — flushing as shortcut", self.eventBuffer.count)
                    self.isBuffering = false
                    self.isModifierDown = false
                    self.flushBuffer()
                    DispatchQueue.main.async { self.onCancelled?() }
                }
            }
            activationWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + activationDelay, execute: work)

            // Let the flagsChanged through (other apps need to see ⌘ state)
            return Unmanaged.passUnretained(event)

        } else if !isDown && isModifierDown {
            // ⌘ released
            isModifierDown = false
            activationWorkItem?.cancel()
            activationWorkItem = nil

            if isActivated {
                // Was recording — stop
                isActivated = false
                isBuffering = false
                NSLog("[Yap] ⌘ RELEASED — stopping recording")
                DispatchQueue.main.async { self.onKeyUp?() }
            } else {
                // Quick tap or shortcut — flush buffered events
                NSLog("[Yap] ⌘ released before activation — flushing %d events", eventBuffer.count)
                flushBuffer()
                DispatchQueue.main.async { self.onCancelled?() }
            }

            return Unmanaged.passUnretained(event)

        } else if hasOtherModifiers && isModifierDown && !isActivated {
            // Another modifier added (e.g. Cmd+Shift) — cancel
            isModifierDown = false
            activationWorkItem?.cancel()
            activationWorkItem = nil
            NSLog("[Yap] Other modifier detected — flushing %d events", eventBuffer.count)
            flushBuffer()
            DispatchQueue.main.async { self.onCancelled?() }
            return Unmanaged.passUnretained(event)
        }

        return Unmanaged.passUnretained(event)
    }

    /// Handle key down/up events during modifier hold
    private func handleKeyEvent(event: CGEvent, proxy: CGEventTapProxy, isDown: Bool) -> Unmanaged<CGEvent>? {

        if isBuffering && isModifierDown && !isActivated {
            // During grace period — INTERCEPT and BUFFER the event
            // Do NOT cancel activation yet — wait for grace period to decide
            if let copy = event.copy() {
                eventBuffer.append((event: copy, proxy: proxy))
            }
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            NSLog("[Yap] Buffered key %@ code=%lld (total: %d)",
                  isDown ? "down" : "up", keyCode, eventBuffer.count)

            // Return nil to SWALLOW the event (don't pass to app yet)
            return nil
        }

        if isActivated {
            // During recording — swallow key events
            return nil
        }

        // Not our concern — pass through
        return Unmanaged.passUnretained(event)
    }

    // MARK: - Event Buffer

    /// Replay buffered events back to the system
    private func flushBuffer() {
        guard !eventBuffer.isEmpty else { return }
        NSLog("[Yap] Flushing %d buffered keyboard events", eventBuffer.count)

        for buffered in eventBuffer {
            buffered.event.post(tap: .cghidEventTap)
        }
        eventBuffer.removeAll()
        isBuffering = false
    }
}
