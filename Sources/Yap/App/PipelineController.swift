import AppKit
import Combine

/// Connects HotkeyManager → AudioRecorder → STT → TextInserter.
/// All methods run on @MainActor.
@MainActor
final class PipelineController {
    static let shared = PipelineController()

    private let recorder = AudioRecorder.shared
    private let state = AppState.shared
    private var durationTimer: Timer?
    private var levelCancellable: AnyCancellable?
    private var recordingStartTime: Date?
    private let minimumDuration: TimeInterval = 0.3

    private init() {
        // Bridge AudioRecorder.audioLevel → AppState.audioLevel
        levelCancellable = recorder.$audioLevel
            .receive(on: RunLoop.main)
            .assign(to: \.audioLevel, on: state)
    }

    // MARK: - Setup

    func setup() {
        let hotkey = HotkeyManager.shared
        hotkey.onKeyDown = { [weak self] in
            Task { @MainActor in self?.startRecording() }
        }
        hotkey.onKeyUp = { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
        hotkey.start()
        NSLog("[Yap] Pipeline ready")
    }

    // MARK: - Recording

    func startRecording() {
        guard !state.isRecording else { return }

        do {
            try recorder.startRecording()
        } catch {
            state.error = "Mic error: \(error.localizedDescription)"
            return
        }

        state.isRecording = true
        state.showOverlay = true
        state.recordingDuration = 0
        state.error = nil
        recordingStartTime = Date()

        SoundFeedback.shared.playStartTone()

        // Duration timer
        durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.state.recordingDuration += 0.1
            }
        }
    }

    func stopRecording() {
        guard state.isRecording else { return }

        let duration = recordingStartTime.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartTime = nil
        durationTimer?.invalidate()
        durationTimer = nil

        let samples = recorder.stopRecording()

        state.isRecording = false
        state.showOverlay = false

        // Too short — cancel
        if duration < minimumDuration {
            NSLog("[Yap] Recording too short (%.2fs), cancelled", duration)
            return
        }

        // Need at least 0.5s of audio (8000 samples at 16kHz)
        guard samples.count > 8000 else {
            state.error = "Too short to transcribe"
            return
        }

        // Silence detection — skip if audio is too quiet (no speech)
        let rms = sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
        NSLog("[Yap] Audio RMS: %.5f", rms)
        guard rms > 0.005 else {
            NSLog("[Yap] Too quiet, skipping transcription")
            return
        }

        SoundFeedback.shared.playStopTone()

        NSLog("[Yap] Transcribing %d samples (%.1fs)", samples.count, Float(samples.count) / 16000)
        state.isTranscribing = true

        Task {
            do {
                let text = try await STTProvider.transcribe(samples)
                guard !text.isEmpty else {
                    state.isTranscribing = false
                    return
                }
                NSLog("[Yap] Transcribed: %@", text)
                state.isTranscribing = false
                state.addTranscription(text)
                TextInserter.insert(text)
                UsageTracker.recordTranscription()
            } catch {
                state.isTranscribing = false
                state.error = error.localizedDescription
                NSLog("[Yap] Transcription error: %@", error.localizedDescription)
            }
        }
    }

    func cancelRecording() {
        guard state.isRecording else { return }
        _ = recorder.stopRecording()
        state.isRecording = false
        state.showOverlay = false
        durationTimer?.invalidate()
        durationTimer = nil
    }
}
