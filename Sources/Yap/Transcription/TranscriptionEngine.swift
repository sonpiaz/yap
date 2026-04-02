import Foundation
import Speech
import AVFoundation

@MainActor
class TranscriptionEngine: ObservableObject {
    static let shared = TranscriptionEngine()

    private var recognizer: SFSpeechRecognizer?
    @Published var isLoaded = false
    @Published var loadingProgress: String = ""

    private init() {}

    func preload() async {
        loadingProgress = "Setting up speech engine..."

        // Try Vietnamese first, fall back to default locale
        if let viRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "vi-VN")),
           viRecognizer.isAvailable {
            self.recognizer = viRecognizer
            print("[Yap] SFSpeechRecognizer loaded: vi-VN")
        } else if let defaultRecognizer = SFSpeechRecognizer() {
            self.recognizer = defaultRecognizer
            print("[Yap] SFSpeechRecognizer loaded: \(defaultRecognizer.locale.identifier) (Vietnamese unavailable)")
        } else {
            loadingProgress = "Speech recognition unavailable"
            print("[Yap] No speech recognizer available")
            return
        }

        // Prefer on-device if available
        if recognizer?.supportsOnDeviceRecognition == true {
            print("[Yap] On-device recognition supported")
        } else {
            print("[Yap] On-device not available — will use server")
        }

        isLoaded = true
        loadingProgress = "Ready"
        AppState.shared.isModelLoaded = true
        print("[Yap] Speech engine ready")
    }

    func transcribe(audioSamples: [Float]) async throws -> YapTranscription {
        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw YapTranscriptionError.modelNotLoaded
        }

        // Convert Float samples (16kHz mono) to an audio file for SFSpeechRecognizer
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("yap_recording.wav")
        try writeWAV(samples: audioSamples, sampleRate: 16000, to: tempURL)

        let request = SFSpeechURLRecognitionRequest(url: tempURL)
        request.shouldReportPartialResults = false
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result = result, result.isFinal else { return }
                continuation.resume(returning: result)
            }
        }

        // Clean up temp file
        try? FileManager.default.removeItem(at: tempURL)

        let text = result.bestTranscription.formattedString
        let locale = recognizer.locale.identifier

        return YapTranscription(
            text: text,
            language: locale,
            segments: result.bestTranscription.segments.map { seg in
                YapSegment(
                    text: seg.substring,
                    start: Float(seg.timestamp),
                    end: Float(seg.timestamp + seg.duration)
                )
            }
        )
    }

    /// Write raw Float PCM samples to a WAV file
    private func writeWAV(samples: [Float], sampleRate: Int, to url: URL) throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
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
        case .modelNotLoaded: return "Speech recognizer not available"
        case .emptyResult: return "No speech detected"
        }
    }
}
