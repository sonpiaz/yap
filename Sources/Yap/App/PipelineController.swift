import Foundation
import AppKit

/// Orchestrates the full pipeline: record → transcribe → process → paste
@MainActor
class PipelineController: ObservableObject {
    static let shared = PipelineController()

    private let recorder = AudioRecorder.shared
    private let engine = TranscriptionEngine.shared
    private let llm = LLMProcessor.shared
    private let state = AppState.shared
    private let overlay = RecordingOverlayController.shared
    private var durationTimer: Timer?

    private init() {}

    func startRecording() {
        guard !state.isRecording else { return }

        do {
            try recorder.startRecording()
            state.isRecording = true
            state.recordingDuration = 0
            state.error = nil

            // Show floating overlay
            overlay.show()

            // Start duration timer
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.state.recordingDuration += 0.1
                    self?.state.audioLevel = self?.recorder.audioLevel ?? 0
                }
            }

            print("[Yap] Recording started")
        } catch {
            state.error = "Mic error: \(error.localizedDescription)"
            print("[Yap] Recording failed: \(error)")
        }
    }

    func stopAndTranscribe() {
        guard state.isRecording else { return }

        let samples = recorder.stopRecording()
        state.isRecording = false

        // Hide overlay and stop timer
        overlay.hide()
        durationTimer?.invalidate()
        durationTimer = nil

        state.isTranscribing = true
        print("[Yap] Recording stopped — \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000))s)")

        // Minimum audio length check (0.5 seconds)
        guard samples.count > 8000 else {
            state.isTranscribing = false
            state.error = "Too short"
            print("[Yap] Audio too short, skipping")
            return
        }

        // Play a subtle sound to confirm recording stopped
        NSSound(named: "Pop")?.play()

        Task {
            await transcribeAndPaste(samples: samples)
        }
    }

    func cancelRecording() {
        if state.isRecording {
            _ = recorder.stopRecording()
            state.isRecording = false
            overlay.hide()
            durationTimer?.invalidate()
            durationTimer = nil
            print("[Yap] Recording cancelled")
        }
    }

    private func transcribeAndPaste(samples: [Float]) async {
        do {
            let result: YapTranscription = try await engine.transcribe(audioSamples: samples)
            print("[Yap] Raw transcription (\(result.language)): \(result.text)")

            guard !result.text.isEmpty else {
                state.isTranscribing = false
                return
            }

            let processed = await llm.process(text: result.text, mode: state.currentMode)
            print("[Yap] Processed (\(state.currentMode.rawValue)): \(processed)")

            TextInserter.insert(processed)

            state.lastTranscription = processed
            state.isTranscribing = false
            state.totalTranscriptions += 1
            state.totalWordsToday += processed.split(separator: " ").count

        } catch {
            state.isTranscribing = false
            state.error = error.localizedDescription
            print("[Yap] Transcription error: \(error)")
        }
    }
}
