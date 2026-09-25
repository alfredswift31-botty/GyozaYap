import Foundation

/// Minimal Claude Messages API client over URLSession (there is no official
/// Swift SDK). Used only when the user adds their own API key.
nonisolated struct ClaudeClient: Sendable {
    static let defaultModel = "claude-opus-5"

    nonisolated enum ClaudeError: LocalizedError {
        case missingKey
        case http(status: Int, message: String)
        case refused
        case truncated
        case emptyResponse

        var errorDescription: String? {
            switch self {
            case .missingKey:
                "Add a Claude API key in Settings to use Claude."
            case let .http(status, message):
                switch status {
                case 401: "Claude rejected the API key. Check it in Settings."
                case 429: "Claude is rate-limiting this key. Try again in a minute."
                case 529: "Claude is overloaded right now. Try again shortly."
                default: "Claude request failed (\(status)): \(message)"
                }
            case .refused:
                "Claude declined to process this transcript."
            case .truncated:
                "Claude's answer was cut off. Try again."
            case .emptyResponse:
                "Claude returned an empty answer."
            }
        }
    }

    let apiKey: String
    var model: String = ClaudeClient.defaultModel
    var session: URLSession = .shared

    /// Sends one user message and returns the concatenated text blocks.
    /// When `schema` is set, the API guarantees the text is JSON matching it.
    func send(system: String, user: String, schema: [String: Any]? = nil, maxTokens: Int = 16000) async throws -> String {
        guard !apiKey.isEmpty else { throw ClaudeError.missingKey }
        do {
            return try await post(system: system, user: user, schema: schema, maxTokens: maxTokens, withFallbacks: true)
        } catch let ClaudeError.http(status, message) where status == 400 && message.localizedCaseInsensitiveContains("fallback") {
            // The fallback beta isn't enabled for this key; the request is
            // still valid without it.
            return try await post(system: system, user: user, schema: schema, maxTokens: maxTokens, withFallbacks: false)
        }
    }

    private func post(system: String, user: String, schema: [String: Any]?, maxTokens: Int, withFallbacks: Bool) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": [["role": "user", "content": user]]
        ]
        if withFallbacks {
            // Server-side fallback: if a safety classifier declines, the API
            // re-runs the request on a recommended fallback model.
            body["fallbacks"] = "default"
        }
        if let schema {
            body["output_config"] = ["format": ["type": "json_schema", "schema": schema]]
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if withFallbacks {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            throw ClaudeError.http(status: status, message: Self.errorMessage(from: data))
        }
        return try Self.text(fromResponse: data)
    }

    /// Pulls the text out of a Messages API response body, checking the stop
    /// reason first as the API requires.
    static func text(fromResponse data: Data) throws -> String {
        let decoded = try JSONDecoder().decode(MessageResponse.self, from: data)
        switch decoded.stopReason {
        case "refusal": throw ClaudeError.refused
        case "max_tokens": throw ClaudeError.truncated
        default: break
        }
        let text = decoded.content
            .filter { $0.type == "text" }
            .compactMap(\.text)
            .joined()
        guard !text.isEmpty else { throw ClaudeError.emptyResponse }
        return text
    }

    static func errorMessage(from data: Data) -> String {
        if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return error.error.message
        }
        return String(data: data, encoding: .utf8) ?? "Unknown error"
    }

    private nonisolated struct MessageResponse: Decodable {
        nonisolated struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stopReason: String?

        enum CodingKeys: String, CodingKey {
            case content
            case stopReason = "stop_reason"
        }
    }

    private nonisolated struct ErrorResponse: Decodable {
        nonisolated struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }
}
