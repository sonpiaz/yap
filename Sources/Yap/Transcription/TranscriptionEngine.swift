import Foundation
import WhisperKit

@MainActor
class TranscriptionEngine: ObservableObject {
    static let shared = TranscriptionEngine()

    private var whisperKit: WhisperKit?
    @Published var isLoaded = false
    @Published var loadingProgress: String = ""

    private init() {}

    func preload() async {
        do {
            loadingProgress = "Downloading model..."
            // Use large-v3 for best Vi/En accuracy. Falls back to base if not enough RAM.
            let config = WhisperKitConfig(
                model: "large-v3",
                computeOptions: ModelComputeOptions(
                    audioEncoderCompute: .cpuAndNeuralEngine,
                    textDecoderCompute: .cpuAndNeuralEngine
                )
            )
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.isLoaded = true
            self.loadingProgress = "Ready"
            print("[Yap] WhisperKit loaded: large-v3")
        } catch {
            print("[Yap] Failed to load large-v3, trying base.en...")
            await loadFallbackModel()
        }
    }

    private func loadFallbackModel() async {
        do {
            let config = WhisperKitConfig(model: "base")
            let kit = try await WhisperKit(config)
            self.whisperKit = kit
            self.isLoaded = true
            self.loadingProgress = "Ready (base model)"
            print("[Yap] WhisperKit loaded: base (fallback)")
        } catch {
            self.loadingProgress = "Failed to load model: \(error.localizedDescription)"
            print("[Yap] WhisperKit failed: \(error)")
        }
    }

    func transcribe(audioSamples: [Float]) async throws -> TranscriptionResult {
        guard let whisperKit = whisperKit else {
            throw TranscriptionError.modelNotLoaded
        }

        // Don't force language — let Whisper auto-detect per segment for Vi/En mixing
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            temperatureFallbackCount: 3,
            sampleLength: 224,
            noSpeechThreshold: 0.6  // Higher threshold to reduce hallucination
        )

        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        guard let result = results.first else {
            throw TranscriptionError.emptyResult
        }

        // Filter out hallucinated segments (very low avg logprob)
        let filteredText = filterHallucinations(result)

        return TranscriptionResult(
            text: filteredText,
            language: result.language ?? "unknown",
            segments: result.segments.map { seg in
                TranscriptionSegment(
                    text: seg.text,
                    start: seg.start,
                    end: seg.end,
                    language: nil
                )
            }
        )
    }

    private func filterHallucinations(_ result: TranscriptionResult) -> String {
        // Filter segments with very low confidence (likely hallucination)
        let validSegments = result.segments.filter { segment in
            // Keep segments that aren't suspiciously repetitive
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            // Filter common hallucination patterns
            let hallPatterns = ["...", "Thank you", "Cảm ơn đã xem", "Hẹn gặp lại"]
            for pattern in hallPatterns {
                if trimmed == pattern { return false }
            }
            return true
        }
        return validSegments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }

    // Overload for WhisperKit's native result type
    private func filterHallucinations(_ result: WhisperKit.TranscriptionResult) -> String {
        let validSegments = result.segments.filter { segment in
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            let hallPatterns = ["...", "Thank you", "Cảm ơn đã xem", "Hẹn gặp lại"]
            for pattern in hallPatterns {
                if trimmed == pattern { return false }
            }
            // Filter by avg log probability if available
            if segment.avgLogprob < -1.5 { return false }
            return true
        }
        return validSegments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

struct TranscriptionResult {
    let text: String
    let language: String
    let segments: [TranscriptionSegment]
}

struct TranscriptionSegment {
    let text: String
    let start: Float
    let end: Float
    let language: String?
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not loaded yet"
        case .emptyResult: return "No speech detected"
        }
    }
}
