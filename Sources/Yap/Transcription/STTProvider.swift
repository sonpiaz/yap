import AVFoundation
import Foundation

// MARK: - STT Provider

enum STTProvider {
    /// Transcribe 16kHz mono Float32 samples using OpenAI gpt-4o-transcribe.
    static func transcribe(_ samples: [Float]) async throws -> String {
        let apiKey = UserDefaults.standard.string(forKey: "openaiApiKey") ?? ""
        guard !apiKey.isEmpty else {
            throw STTError.noApiKey
        }

        let wavData = try createWAV(samples: samples, sampleRate: 16000)
        return try await callOpenAI(apiKey: apiKey, wavData: wavData)
    }

    // MARK: - OpenAI API

    private static func callOpenAI(apiKey: String, wavData: Data) async throws -> String {
        let boundary = UUID().uuidString
        let model = "gpt-4o-transcribe"
        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // file
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"recording.wav\"\r\n")
        body.append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        body.append("\r\n")

        // model
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        body.append("\(model)\r\n")

        // prompt — helps with Vietnamese + English mixed speech
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
        body.append("This audio may contain Vietnamese and English mixed speech. Transcribe accurately.\r\n")

        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw STTError.networkError
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw STTError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw STTError.parseError
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - WAV Encoder

    private static func createWAV(samples: [Float], sampleRate: Int) throws -> Data {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: false
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yap_\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: tmpURL, settings: format.settings)
        try file.write(from: buffer)
        let data = try Data(contentsOf: tmpURL)
        try? FileManager.default.removeItem(at: tmpURL)
        return data
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func append(_ string: String) {
        append(string.data(using: .utf8)!)
    }
}

// MARK: - Errors

enum STTError: LocalizedError {
    case noApiKey
    case networkError
    case apiError(Int, String)
    case parseError

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No OpenAI API key — add in Settings (⌘,)"
        case .networkError: return "Network error"
        case .apiError(let code, let msg): return "API error \(code): \(msg)"
        case .parseError: return "Failed to parse response"
        }
    }
}
