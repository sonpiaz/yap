import Foundation

actor LLMProcessor {
    static let shared = LLMProcessor()

    private init() {}

    func process(text: String, mode: TranscriptionMode) async -> String {
        switch mode {
        case .raw:
            return text
        case .clean:
            return await cleanWithLLM(text)
        case .smart:
            return await smartFormat(text)
        }
    }

    // MARK: - Clean mode: remove fillers, fix punctuation

    private func cleanWithLLM(_ text: String) async -> String {
        // Try Ollama first (local), then Claude API
        if let result = try? await ollamaClean(text) {
            return result
        }
        if let result = try? await claudeClean(text) {
            return result
        }
        // Fallback: basic cleanup without LLM
        return basicClean(text)
    }

    private func smartFormat(_ text: String) async -> String {
        if let result = try? await ollamaSmart(text) {
            return result
        }
        if let result = try? await claudeSmart(text) {
            return result
        }
        return await cleanWithLLM(text)
    }

    // MARK: - Ollama (local)

    private func ollamaClean(_ text: String) async throws -> String {
        let prompt = """
        Fix this speech transcription. It may mix Vietnamese and English. \
        Remove filler words (ừm, à, uh, um, like). Fix punctuation and capitalization. \
        Keep the original language mix — do NOT translate. Output ONLY the cleaned text.

        Input: \(text)
        """
        return try await callOllama(prompt: prompt)
    }

    private func ollamaSmart(_ text: String) async throws -> String {
        let prompt = """
        Format this speech transcription intelligently. It may mix Vietnamese and English.
        Rules:
        - Remove filler words
        - Fix punctuation and capitalization
        - Add paragraph breaks where topics change
        - If it sounds like a list, format as bullet points
        - If it contains code terms, preserve them exactly (camelCase, snake_case, etc.)
        - Keep the original language mix — do NOT translate
        - Output ONLY the formatted text

        Input: \(text)
        """
        return try await callOllama(prompt: prompt)
    }

    private func callOllama(prompt: String) async throws -> String {
        let url = URL(string: "http://localhost:11434/api/generate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": UserDefaults.standard.string(forKey: "ollamaModel") ?? "llama3.2",
            "prompt": prompt,
            "stream": false,
            "options": ["temperature": 0.1]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw LLMError.ollamaUnavailable
        }

        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let result = json["response"] as? String {
            return result.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw LLMError.parseError
    }

    // MARK: - Claude API (cloud fallback)

    private func claudeClean(_ text: String) async throws -> String {
        let prompt = """
        Fix this speech transcription. It may mix Vietnamese and English. \
        Remove filler words. Fix punctuation. Keep original language mix. Output ONLY cleaned text.

        \(text)
        """
        return try await callClaude(prompt: prompt)
    }

    private func claudeSmart(_ text: String) async throws -> String {
        let prompt = """
        Format this speech transcription. May mix Vietnamese and English.
        - Remove fillers, fix punctuation
        - Add paragraphs/bullets where appropriate
        - Preserve code terms exactly
        - Keep original language mix
        Output ONLY the formatted text.

        \(text)
        """
        return try await callClaude(prompt: prompt)
    }

    private func callClaude(prompt: String) async throws -> String {
        guard let apiKey = UserDefaults.standard.string(forKey: "claudeApiKey"),
              !apiKey.isEmpty else {
            throw LLMError.noApiKey
        }

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 1024,
            "messages": [
                ["role": "user", "content": prompt]
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

    // MARK: - Basic cleanup (no LLM)

    private func basicClean(_ text: String) -> String {
        var cleaned = text
        let fillers = ["ừm", "à", "uh", "um", "like", "you know", "basically"]
        for filler in fillers {
            cleaned = cleaned.replacingOccurrences(
                of: "\\b\(filler)\\b",
                with: "",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        // Collapse multiple spaces
        cleaned = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return cleaned.trimmingCharacters(in: .whitespaces)
    }
}

enum LLMError: LocalizedError {
    case ollamaUnavailable
    case noApiKey
    case claudeError
    case parseError

    var errorDescription: String? {
        switch self {
        case .ollamaUnavailable: return "Ollama not running (localhost:11434)"
        case .noApiKey: return "No Claude API key configured"
        case .claudeError: return "Claude API error"
        case .parseError: return "Failed to parse LLM response"
        }
    }
}
