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
            print("[Yap] Failed to load large-v3, trying base...")
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

    func transcribe(audioSamples: [Float]) async throws -> YapTranscription {
        guard let whisperKit = whisperKit else {
            throw YapTranscriptionError.modelNotLoaded
        }

        // Don't force language — let Whisper auto-detect per segment for Vi/En mixing
        let options = DecodingOptions(
            verbose: false,
            task: .transcribe,
            temperatureFallbackCount: 3,
            sampleLength: 224,
            noSpeechThreshold: 0.6
        )

        let results = try await whisperKit.transcribe(
            audioArray: audioSamples,
            decodeOptions: options
        )

        guard let result = results.first else {
            throw YapTranscriptionError.emptyResult
        }

        let filteredText = filterHallucinations(from: result)

        return YapTranscription(
            text: filteredText,
            language: result.language ?? "unknown",
            segments: result.segments.map { seg in
                YapSegment(
                    text: seg.text,
                    start: seg.start,
                    end: seg.end
                )
            }
        )
    }

    private func filterHallucinations(from result: TranscriptionResult) -> String {
        let hallPatterns = ["...", "Thank you", "Cảm ơn đã xem", "Hẹn gặp lại",
                           "Đăng ký kênh", "Subscribe", "Thanks for watching"]

        let validSegments = result.segments.filter { segment in
            let trimmed = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return false }
            if hallPatterns.contains(trimmed) { return false }
            if segment.avgLogprob < -1.5 { return false }
            return true
        }
        return validSegments.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespaces)
    }
}

struct YapTranscription {
    let text: String
    let language: String
    let segments: [YapSegment]
}

struct YapSegment {
    let text: String
    let start: Float
    let end: Float
}

enum YapTranscriptionError: LocalizedError {
    case modelNotLoaded
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "Whisper model not loaded yet"
        case .emptyResult: return "No speech detected"
        }
    }
}
