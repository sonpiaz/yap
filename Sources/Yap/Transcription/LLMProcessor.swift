import Foundation

actor LLMProcessor {
    static let shared = LLMProcessor()

    private init() {}

    func process(text: String, mode: TranscriptionMode) async -> String {
        switch mode {
        case .raw:
            return text
        case .clean:
            return basicClean(text)
        case .smart:
            if let result = try? await claudeSmart(text) {
                return result
            }
            return basicClean(text)
        }
    }

    // MARK: - Basic cleanup (no LLM)

    private func basicClean(_ text: String) -> String {
        var cleaned = text
        let fillers = ["ừm", "à", "uh", "um", "like", "you know", "basically", "ờ", "thì là", "cái này"]
        for filler in fillers {
            cleaned = cleaned.replacingOccurrences(
                of: "\\b\(filler)\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Claude Haiku (fast cloud)

    private func claudeSmart(_ text: String) async throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: "claudeApiKey"),
              !apiKey.isEmpty else {
            throw LLMError.noApiKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": """
                Format this speech transcription. It may mix Vietnamese and English.
                - Remove filler words (ừm, à, uh, um)
                - Fix punctuation and capitalization
                - Keep the original language — do NOT translate
                - Output ONLY the formatted text, nothing else

                \(text)
                """]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.claudeError
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let content = json["content"] as? [[String: Any]],
           let text = content.first?["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw LLMError.parseError
    }
}

enum LLMError: LocalizedError {
    case noApiKey
    case claudeError
    case parseError

    var errorDescription: String? {
        switch self {
        case .noApiKey: return "No Claude API key configured"
        case .claudeError: return "Claude API error"
        case .parseError: return "Failed to parse LLM response"
        }
    }
}
