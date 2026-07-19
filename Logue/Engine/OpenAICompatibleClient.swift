import Foundation

// MARK: - OpenAICompatibleClient

/// Client for OpenAI-compatible API endpoints (local or remote)
actor OpenAICompatibleClient: LLMClient {
    let endpoint: String
    let apiKey: String?
    let modelName: String

    init(endpoint: String, apiKey: String? = nil, modelName: String = "gpt-3.5-turbo") {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
    }

    /// Builds a URLRequest with appropriate headers. Only attaches Authorization for secure endpoints.
    private func makeRequest(path: String, method: String = "POST") throws -> URLRequest {
        guard let url = URL(string: "\(endpoint)\(path)") else {
            throw LLMClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Only send API key over HTTPS or to localhost to prevent credential exfiltration
        if let apiKey, isEndpointSecure(endpoint) {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    // MARK: - LLMClient Protocol

    func chat(messages: [LLMMessage], temperature: Double = 0.7, maxTokens: Int = 512) async throws -> String {
        let openAIMessages = messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) }
        return try await chatWithOpenAIMessages(openAIMessages, temperature: temperature, maxTokens: maxTokens)
    }

    func streamChat(messages: [LLMMessage], temperature: Double = 0.7, maxTokens: Int = 512) -> AsyncThrowingStream<String, Error> {
        let openAIMessages = messages.map { OpenAIMessage(role: $0.role.rawValue, content: $0.content) }
        return streamWithOpenAIMessages(openAIMessages, temperature: temperature, maxTokens: maxTokens)
    }

    func testConnection() async throws {
        _ = try await chat(
            messages: [LLMMessage(role: .user, content: "Hello")],
            temperature: 0.0,
            maxTokens: 10
        )
    }

    func listModels() async throws -> [String] {
        var request = try makeRequest(path: "/models", method: "GET")
        request.httpBody = nil
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            return []
        }

        struct ModelsResponse: Decodable {
            struct ModelData: Decodable { let id: String }
            let data: [ModelData]
        }

        if let modelsResp = try? JSONDecoder().decode(ModelsResponse.self, from: data) {
            return modelsResp.data.map(\.id)
        }
        return []
    }

    // MARK: - Legacy OpenAIMessage API (used by LLMEngine internally)

    func chatWithOpenAIMessages(_ messages: [OpenAIMessage], temperature: Double = 0.7, maxTokens: Int = 512) async throws -> String {
        var request = try makeRequest(path: "/chat/completions")

        let requestBody = ChatCompletionRequest(
            model: modelName,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )

        request.httpBody = try JSONEncoder().encode(requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMClientError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                throw LLMClientError.apiError(errorResponse.error.message)
            }
            throw LLMClientError.httpError(httpResponse.statusCode)
        }

        let completionResponse = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        guard let content = completionResponse.choices.first?.message.content else {
            throw LLMClientError.emptyResponse
        }

        return content
    }

    func streamWithOpenAIMessages(
        _ messages: [OpenAIMessage],
        temperature: Double = 0.7,
        maxTokens: Int = 512
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = try makeRequest(path: "/chat/completions")
                    request.setValue("text/event-stream", forHTTPHeaderField: "Accept")

                    let requestBody = ChatCompletionRequest(
                        model: modelName,
                        messages: messages,
                        temperature: temperature,
                        maxTokens: maxTokens,
                        stream: true
                    )

                    request.httpBody = try JSONEncoder().encode(requestBody)

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200
                    else {
                        continuation.finish(throwing: LLMClientError.invalidResponse)
                        return
                    }

                    for try await line in bytes.lines where line.hasPrefix("data: ") {
                        if Task.isCancelled {
                            break
                        }
                        let data = line.dropFirst(6)
                        if data == "[DONE]" {
                            break
                        }

                        if let jsonData = data.data(using: .utf8),
                           let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
                           let content = chunk.choices.first?.delta.content
                        {
                            continuation.yield(content)
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
}

// MARK: - Models

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case stream
    }

    init(model: String, messages: [OpenAIMessage], temperature: Double, maxTokens: Int, stream: Bool? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
    }
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]

    struct Choice: Codable {
        let message: OpenAIMessage
    }
}

struct ChatCompletionChunk: Codable {
    let choices: [ChoiceDelta]

    struct ChoiceDelta: Codable {
        let delta: Delta
    }

    struct Delta: Codable {
        let content: String?
    }
}

struct OpenAIErrorResponse: Codable {
    let error: ErrorDetail

    struct ErrorDetail: Codable {
        let message: String
    }
}

// MARK: - Errors
