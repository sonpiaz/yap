import Foundation
import AppKit

@MainActor
class PipelineController: ObservableObject {
    static let shared = PipelineController()

    private let recorder = AudioRecorder.shared
    private let state = AppState.shared
    private var durationTimer: Timer?

    private init() {}

    func startRecording() {
        guard !state.isRecording else { return }

        do {
            try recorder.startRecording()
            state.isRecording = true
            state.recordingDuration = 0
            state.error = nil
            
            durationTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.state.recordingDuration += 0.1
                    self?.state.audioLevel = self?.recorder.audioLevel ?? 0
                }
            }
        } catch {
            state.error = "Mic error: \(error.localizedDescription)"
        }
    }

    func stopAndTranscribe() {
        guard state.isRecording else { return }

        let samples = recorder.stopRecording()
        state.isRecording = false
        durationTimer?.invalidate()
        durationTimer = nil
        
        // Need at least 0.5s of audio
        guard samples.count > 8000 else {
            state.error = "Too short"
            return
        }

        state.isTranscribing = true
                NSSound(named: "Pop")?.play()

        Task {
            do {
                let text = try await STTProvider.transcribe(audioSamples: samples)

                guard !text.isEmpty else {
                    state.isTranscribing = false
                                        return
                }

                state.addTranscription(text)
                state.isTranscribing = false
                
            } catch {
                state.isTranscribing = false
                state.error = error.localizedDescription
                            }
        }
    }

    func cancelRecording() {
        if state.isRecording {
            _ = recorder.stopRecording()
            state.isRecording = false
            durationTimer?.invalidate()
            durationTimer = nil
                    }
    }
}
