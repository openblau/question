import Foundation

/// Minimal streaming client for the Claude Messages API (raw HTTP + SSE).
///
/// Privacy: uses an *ephemeral* URLSession — no cookies, no URL cache, no
/// credential storage. Nothing is ever written to disk by this client.
@MainActor
struct ClaudeClient {
    static let model = "claude-opus-5-5"
    static let effort = "medium"   // quick lookups; raise to "high" for harder questions

    enum StreamEvent {
        case text(String)
        case status(String)
        case source(title: String, url: String)
    }

    struct Result {
        var content: [[String: Any]]
        var stopReason: String?
    }

    struct APIError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    let apiKey: String
    let system: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 600
        return URLSession(configuration: config)
    }()

    func stream(messages: [[String: Any]], onEvent: (StreamEvent) -> Void) async throws -> Result {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body: [String: Any] = [
            "model": Self.model,
            "max_tokens": 64000,
            "stream": true,
            "system": system,
            "thinking": ["type": "adaptive"],
            "output_config": ["effort": Self.effort],
            // On a safety-classifier refusal, the API re-runs on a fallback model.
            "fallbacks": "default",
            "tools": [["type": "web_search_20260209", "name": "web_search", "max_uses": 5]],
            "messages": messages,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await Self.session.bytes(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            var raw = ""
            for try await line in bytes.lines { raw += line }
            throw APIError(message: Self.describeError(status: status, body: raw))
        }

        var blocks: [Int: [String: Any]] = [:]
        var partialJSON: [Int: String] = [:]
        var stopReason: String?

        for try await line in bytes.lines {
            try Task.checkCancellation()
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }

            switch type {
            case "content_block_start":
                guard let index = event["index"] as? Int,
                      let block = event["content_block"] as? [String: Any] else { break }
                blocks[index] = block
                switch block["type"] as? String {
                case "thinking": onEvent(.status("Thinking…"))
                case "server_tool_use": onEvent(.status("Searching the web…"))
                case "web_search_tool_result": onEvent(.status("Reading results…"))
                case "text":
                    if let text = block["text"] as? String, !text.isEmpty { onEvent(.text(text)) }
                default: break
                }

            case "content_block_delta":
                guard let index = event["index"] as? Int,
                      let delta = event["delta"] as? [String: Any],
                      var block = blocks[index] else { break }
                switch delta["type"] as? String {
                case "text_delta":
                    let piece = delta["text"] as? String ?? ""
                    block["text"] = (block["text"] as? String ?? "") + piece
                    onEvent(.text(piece))
                case "thinking_delta":
                    block["thinking"] = (block["thinking"] as? String ?? "") + (delta["thinking"] as? String ?? "")
                case "signature_delta":
                    block["signature"] = (block["signature"] as? String ?? "") + (delta["signature"] as? String ?? "")
                case "input_json_delta":
                    partialJSON[index, default: ""] += delta["partial_json"] as? String ?? ""
                case "citations_delta":
                    if let citation = delta["citation"] as? [String: Any] {
                        var citations = block["citations"] as? [[String: Any]] ?? []
                        citations.append(citation)
                        block["citations"] = citations
                        if let url = citation["url"] as? String {
                            onEvent(.source(title: citation["title"] as? String ?? url, url: url))
                        }
                    }
                default: break
                }
                blocks[index] = block

            case "content_block_stop":
                guard let index = event["index"] as? Int, let json = partialJSON.removeValue(forKey: index) else { break }
                let parsed = json.isEmpty ? [:] : (try? JSONSerialization.jsonObject(with: Data(json.utf8))) ?? [:]
                blocks[index]?["input"] = parsed

            case "message_delta":
                if let delta = event["delta"] as? [String: Any], let reason = delta["stop_reason"] as? String {
                    stopReason = reason
                }

            case "error":
                let error = event["error"] as? [String: Any]
                throw APIError(message: error?["message"] as? String ?? "Stream error")

            default: break
            }
        }

        let content = blocks.keys.sorted().compactMap { blocks[$0] }
        return Result(content: content, stopReason: stopReason)
    }

    private static func describeError(status: Int, body: String) -> String {
        let message = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])
            .flatMap { $0["error"] as? [String: Any] }
            .flatMap { $0["message"] as? String }
        switch status {
        case 401: return "Invalid API key. Use the menu bar icon → Forget API Key, then paste a new one."
        case 429: return "Rate limited — try again in a moment."
        default: return "HTTP \(status): \(message ?? body.prefix(300).description)"
        }
    }
}
