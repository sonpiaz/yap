import Foundation

/// Orchestrates the full pipeline: record → transcribe → process → paste
@MainActor
class PipelineController: ObservableObject {
    static let shared = PipelineController()

    private let recorder = AudioRecorder.shared
    private let engine = TranscriptionEngine.shared
    private let llm = LLMProcessor.shared
    private let state = AppState.shared

    private init() {}

    func startRecording() {
        guard !state.isRecording else { return }

        do {
            try recorder.startRecording()
            state.isRecording = true
            state.error = nil
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
        state.isTranscribing = true
        print("[Yap] Recording stopped — \(samples.count) samples (\(String(format: "%.1f", Double(samples.count) / 16000))s)")

        // Minimum audio length check (0.5 seconds)
        guard samples.count > 8000 else {
            state.isTranscribing = false
            state.error = "Too short"
            print("[Yap] Audio too short, skipping")
            return
        }

        Task {
            await transcribeAndPaste(samples: samples)
        }
    }

    func cancelRecording() {
        if state.isRecording {
            _ = recorder.stopRecording()
            state.isRecording = false
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

            // Step 2: LLM processing based on mode
            let processed = await llm.process(text: result.text, mode: state.currentMode)
            print("[Yap] Processed (\(state.currentMode.rawValue)): \(processed)")

            // Step 3: Insert into active app
            TextInserter.insert(processed)

            // Update state
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
