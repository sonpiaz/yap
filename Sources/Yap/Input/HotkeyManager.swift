import Cocoa
import KeyboardShortcuts
import Combine

// Register the shortcut name
extension KeyboardShortcuts.Name {
    static let pushToTalk = Self("pushToTalk", default: .init(.space, modifiers: .option))
}

class HotkeyManager: ObservableObject {
    static let shared = HotkeyManager()

    private var isHotkeyDown = false
    private var recordingStartTime: Date?
    private let minimumRecordingDuration: TimeInterval = 0.3

    private init() {
        setupHandlers()
    }

    func setup() {
        // KeyboardShortcuts registers via Carbon API — no Accessibility needed
        print("[Yap] Hotkey registered — no Accessibility needed")
        print("[Yap] Push-to-talk: Option+Space (default)")
    }

    private func setupHandlers() {
        KeyboardShortcuts.onKeyDown(for: .pushToTalk) { [weak self] in
            self?.handleKeyDown()
        }

        KeyboardShortcuts.onKeyUp(for: .pushToTalk) { [weak self] in
            self?.handleKeyUp()
        }
    }

    private func handleKeyDown() {
        guard !isHotkeyDown else { return }
        isHotkeyDown = true
        recordingStartTime = Date()
        DispatchQueue.main.async {
            PipelineController.shared.startRecording()
        }
    }

    private func handleKeyUp() {
        guard isHotkeyDown else { return }
        isHotkeyDown = false

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
        KeyboardShortcuts.disable(.pushToTalk)
    }
}
