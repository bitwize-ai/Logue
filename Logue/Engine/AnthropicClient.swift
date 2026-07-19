import Foundation

// MARK: - AnthropicClient

/// Client for the Anthropic Messages API (Claude models).
actor AnthropicClient: LLMClient {
    let apiKey: String
    let modelName: String
    let endpoint: String

    init(apiKey: String, modelName: String = "claude-sonnet-4-6", endpoint: String = "https://api.anthropic.com") {
        self.apiKey = apiKey
        self.modelName = modelName
        self.endpoint = endpoint
    }

    // MARK: - LLMClient

    func chat(messages: [LLMMessage], temperature: Double = 0.7, maxTokens: Int = 512) async throws -> String {
        let request = try buildRequest(messages: messages, temperature: temperature, maxTokens: maxTokens, stream: false)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data) {
                throw LLMClientError.apiError(errorResponse.error.message)
            }
            throw LLMClientError.httpError(httpResponse.statusCode)
        }

        let messageResponse = try JSONDecoder().decode(AnthropicMessageResponse.self, from: data)
        guard let textBlock = messageResponse.content.first(where: { $0.type == "text" }) else {
            throw LLMClientError.emptyResponse
        }
        return textBlock.text ?? ""
    }

    func streamChat(messages: [LLMMessage], temperature: Double = 0.7, maxTokens: Int = 512) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try buildRequest(messages: messages, temperature: temperature, maxTokens: maxTokens, stream: true)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                        continuation.finish(throwing: LLMClientError.invalidResponse)
                        return
                    }

                    for try await line in bytes.lines {
                        if Task.isCancelled {
                            break
                        }

                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            guard let jsonData = data.data(using: .utf8) else { continue }

                            if let event = try? JSONDecoder().decode(AnthropicStreamEvent.self, from: jsonData) {
                                switch event.type {
                                case "content_block_delta":
                                    if let delta = event.delta, delta.type == "text_delta", let text = delta.text {
                                        continuation.yield(text)
                                    }
                                case "message_stop":
                                    break
                                default:
                                    continue
                                }
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func testConnection() async throws {
        _ = try await chat(
            messages: [LLMMessage(role: .user, content: "Hello")],
            temperature: 0.0,
            maxTokens: 10
        )
    }

    func listModels() async throws -> [String] {
        guard let url = URL(string: "\(endpoint)/v1/models") else {
            throw LLMClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if isEndpointSecure(endpoint) {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            // Fallback to known models if listing fails
            return Self.knownModels
        }

        struct ModelsResponse: Decodable {
            struct ModelData: Decodable { let id: String }
            let data: [ModelData]
        }

        if let modelsResp = try? JSONDecoder().decode(ModelsResponse.self, from: data) {
            return modelsResp.data.map(\.id)
        }

        return Self.knownModels
    }

    // MARK: - Known Models

    static let knownModels: [String] = [
        // Claude 4.6
        "claude-opus-4-6",
        "claude-sonnet-4-6",
        // Claude 4.5
        "claude-haiku-4-5-20251001",
        "claude-opus-4-5-20251101",
        "claude-sonnet-4-5-20250929",
        // Claude 4
        "claude-opus-4-20250514",
        "claude-sonnet-4-20250514",
    ]

    // MARK: - Request Building

    private func buildRequest(messages: [LLMMessage], temperature: Double, maxTokens: Int, stream: Bool) throws -> URLRequest {
        guard let url = URL(string: "\(endpoint)/v1/messages") else {
            throw LLMClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Only send API key over HTTPS or to localhost to prevent credential exfiltration
        if isEndpointSecure(endpoint) {
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        }
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        if stream {
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        }

        // Extract system message and build Anthropic request
        var systemText: String?
        var apiMessages: [AnthropicMessage] = []

        for message in messages {
            if message.role == .system {
                systemText = message.content
            } else {
                apiMessages.append(AnthropicMessage(
                    role: message.role == .assistant ? "assistant" : "user",
                    content: message.content
                ))
            }
        }

        let requestBody = AnthropicRequest(
            model: modelName,
            maxTokens: maxTokens,
            system: systemText,
            messages: apiMessages,
            temperature: temperature,
            stream: stream
        )

        request.httpBody = try JSONEncoder().encode(requestBody)
        return request
    }
}

// MARK: - Request/Response Types

private struct AnthropicMessage: Codable {
    let role: String
    let content: String
}

private struct AnthropicRequest: Codable {
    let model: String
    let maxTokens: Int
    let system: String?
    let messages: [AnthropicMessage]
    let temperature: Double
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case system
        case messages
        case temperature
        case stream
    }
}

struct AnthropicMessageResponse: Codable {
    let content: [ContentBlock]

    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
}

private struct AnthropicStreamEvent: Codable {
    let type: String
    let delta: Delta?

    struct Delta: Codable {
        let type: String?
        let text: String?
    }
}

private struct AnthropicErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let message: String
    }
}

// MARK: - Errors
