import Foundation
import AVFoundation

// MARK: - Provider Enum

enum STTProviderType: String, CaseIterable, Identifiable {
    case groq = "Groq"
    case openai = "OpenAI"
    case deepgram = "Deepgram"

    var id: String { rawValue }

    var apiKeyKey: String {
        switch self {
        case .groq: return "groqApiKey"
        case .openai: return "openaiApiKey"
        case .deepgram: return "deepgramApiKey"
        }
    }

    var description: String {
        switch self {
        case .groq: return "Whisper Large v3 Turbo — fast, cheap"
        case .openai: return "Whisper-1 — reliable"
        case .deepgram: return "Nova-3 — best Vietnamese"
        }
    }
}

// MARK: - Language

enum STTLanguage: String, CaseIterable, Identifiable {
    case auto = "Auto-detect"
    case vi = "Vietnamese"
    case en = "English"

    var id: String { rawValue }

    var code: String? {
        switch self {
        case .auto: return nil
        case .vi: return "vi"
        case .en: return "en"
        }
    }
}

// MARK: - STT Provider

enum STTProvider {

    static func transcribe(audioSamples: [Float]) async throws -> String {
        let providerRaw = UserDefaults.standard.string(forKey: "sttProvider") ?? STTProviderType.groq.rawValue
        let provider = STTProviderType(rawValue: providerRaw) ?? .groq

        guard let apiKey = UserDefaults.standard.string(forKey: provider.apiKeyKey),
              !apiKey.isEmpty else {
            throw STTError.noApiKey(provider)
        }

        let langRaw = UserDefaults.standard.string(forKey: "sttLanguage") ?? STTLanguage.auto.rawValue
        let language = STTLanguage(rawValue: langRaw) ?? .auto

        let wavData = try AudioConverter.createWAV(samples: audioSamples, sampleRate: 16000)

        switch provider {
        case .groq:
            return try await transcribeWhisperAPI(
                baseURL: "https://api.groq.com/openai/v1/audio/transcriptions",
                model: "whisper-large-v3-turbo",
                apiKey: apiKey,
                wavData: wavData,
                language: language
            )
        case .openai:
            return try await transcribeWhisperAPI(
                baseURL: "https://api.openai.com/v1/audio/transcriptions",
                model: "whisper-1",
                apiKey: apiKey,
                wavData: wavData,
                language: language
            )
        case .deepgram:
            return try await transcribeDeepgram(apiKey: apiKey, wavData: wavData, language: language)
        }
    }

    // MARK: - Whisper-compatible API (OpenAI + Groq)

    private static func transcribeWhisperAPI(
        baseURL: String,
        model: String,
        apiKey: String,
        wavData: Data,
        language: STTLanguage
    ) async throws -> String {
        let boundary = UUID().uuidString
        let url = URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // file
        body.appendMultipart(boundary: boundary, name: "file", filename: "recording.wav", contentType: "audio/wav", data: wavData)
        // model
        body.appendMultipart(boundary: boundary, name: "model", value: model)
        // language (optional)
        if let langCode = language.code {
            body.appendMultipart(boundary: boundary, name: "language", value: langCode)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

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

    // MARK: - Deepgram API

    private static func transcribeDeepgram(
        apiKey: String,
        wavData: Data,
        language: STTLanguage
    ) async throws -> String {
        var urlString = "https://api.deepgram.com/v1/listen?model=nova-3&smart_format=true"
        if let langCode = language.code {
            urlString += "&language=\(langCode)"
        } else {
            urlString += "&detect_language=true"
        }

        let url = URL(string: urlString)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("audio/wav", forHTTPHeaderField: "Content-Type")
        request.httpBody = wavData

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw STTError.networkError
        }
        guard http.statusCode == 200 else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown"
            throw STTError.apiError(http.statusCode, msg)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [String: Any],
              let channels = results["channels"] as? [[String: Any]],
              let firstChannel = channels.first,
              let alternatives = firstChannel["alternatives"] as? [[String: Any]],
              let firstAlt = alternatives.first,
              let transcript = firstAlt["transcript"] as? String else {
            throw STTError.parseError
        }

        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Audio Converter

enum AudioConverter {
    static func createWAV(samples: [Float], sampleRate: Int) throws -> Data {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)

        let channelData = buffer.floatChannelData![0]
        for i in 0..<samples.count {
            channelData[i] = samples[i]
        }

        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("yap_\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        try file.write(from: buffer)

        let data = try Data(contentsOf: tempURL)
        try? FileManager.default.removeItem(at: tempURL)
        return data
    }
}

// MARK: - Errors

enum STTError: LocalizedError {
    case networkError
    case apiError(Int, String)
    case parseError
    case noApiKey(STTProviderType)

    var errorDescription: String? {
        switch self {
        case .networkError: return "Network error"
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .parseError: return "Failed to parse response"
        case .noApiKey(let provider): return "No \(provider.rawValue) API key — add in Settings"
        }
    }
}

// MARK: - Data Extension

private extension Data {
    mutating func appendMultipart(boundary: String, name: String, filename: String, contentType: String, data: Data) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        append(data)
        append("\r\n".data(using: .utf8)!)
    }

    mutating func appendMultipart(boundary: String, name: String, value: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}
