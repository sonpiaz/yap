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

        let mode = TranscriptionMode.current
        let wavData = try createWAV(samples: samples, sampleRate: 16000)
        var text = try await callOpenAI(apiKey: apiKey, wavData: wavData, prompt: mode.sttPrompt)

        // Post-process with GPT-4o if mode requires rewrite
        if mode.needsRewrite, !text.isEmpty {
            text = try await rewriteWithGPT(apiKey: apiKey, text: text, systemPrompt: mode.rewritePrompt)
        }

        return text
    }

    // MARK: - OpenAI API

    private static func callOpenAI(apiKey: String, wavData: Data, prompt: String) async throws -> String {
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

        // prompt
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"prompt\"\r\n\r\n")
        body.append("\(prompt)\r\n")

        // language hint — Vietnamese primary (handles English mixed in)
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n")
        body.append("vi\r\n")

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

    // MARK: - GPT-4o Rewrite

    private static func rewriteWithGPT(apiKey: String, text: String, systemPrompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini",
            "temperature": 0.3,
            "max_tokens": 1024,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            NSLog("[Yap] Rewrite failed, using raw transcription")
            return text // fallback to raw transcription
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            return text
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - WAV Encoder

    private static func createWAV(samples: [Float], sampleRate: Int) throws -> Data {
        // Convert Float32 → Int16 PCM (more reliable for OpenAI API)
        let int16Format = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Double(sampleRate),
            channels: 1,
            interleaved: true
        )!
        let buffer = AVAudioPCMBuffer(pcmFormat: int16Format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let int16Data = buffer.int16ChannelData![0]
        for i in 0..<samples.count {
            int16Data[i] = Int16(max(-1, min(1, samples[i])) * Float(Int16.max))
        }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("yap_\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: tmpURL, settings: int16Format.settings)
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
