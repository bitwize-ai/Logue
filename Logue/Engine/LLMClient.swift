import Foundation

// MARK: - LLMMessage

/// Unified message type used across all LLM providers.
struct LLMMessage {
    enum Role: String {
        case system
        case user
        case assistant
    }

    let role: Role
    let content: String
}

// MARK: - LLMClient Protocol

/// Abstraction over different LLM API providers (OpenAI, Anthropic, OpenRouter, etc.).
protocol LLMClient: Actor, Sendable {
    /// Non-streaming chat completion. Returns the full response text.
    func chat(messages: [LLMMessage], temperature: Double, maxTokens: Int) async throws -> String

    /// Streaming chat completion. Yields tokens as they arrive.
    func streamChat(messages: [LLMMessage], temperature: Double, maxTokens: Int) -> AsyncThrowingStream<String, Error>

    /// Quick connection health check.
    func testConnection() async throws

    /// Discovers available model IDs from the provider's endpoint.
    func listModels() async throws -> [String]
}

// MARK: - Unified Error Type

/// Shared error type for all LLM API clients.
enum LLMClientError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case emptyResponse
    case httpError(Int)
    case apiError(String)
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid API endpoint URL"
        case .invalidResponse: "Invalid response from API"
        case .emptyResponse: "Empty response from API"
        case let .httpError(code): "HTTP error: \(code)"
        case let .apiError(message): "API error: \(message)"
        case .signingFailed: "Request signing failed"
        }
    }
}

// MARK: - Endpoint Security

extension URL {
    /// Returns true if this endpoint is safe to send credentials to (HTTPS or localhost).
    var isEndpointSecure: Bool {
        guard let components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return false }
        let scheme = components.scheme?.lowercased() ?? ""
        let host = components.host?.lowercased() ?? ""
        if scheme == "https" {
            return true
        }
        if scheme == "http", host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return true
        }
        return false
    }

    /// Returns true if this URL targets a private/internal network (SSRF protection).
    /// Blocks RFC-1918, link-local, loopback (non-localhost), and cloud metadata endpoints.
    var isPrivateOrMetadataEndpoint: Bool {
        guard let host = host?.lowercased() else { return true }
        let blockedPrefixes = [
            "10.", "172.16.", "172.17.", "172.18.", "172.19.",
            "172.20.", "172.21.", "172.22.", "172.23.", "172.24.",
            "172.25.", "172.26.", "172.27.", "172.28.", "172.29.",
            "172.30.", "172.31.", "192.168.", "169.254.",
            "fc00:", "fd00:", "fe80:",
        ]
        for prefix in blockedPrefixes where host.hasPrefix(prefix) {
            return true
        }
        if host == "metadata.google.internal" {
            return true
        }
        return false
    }
}

/// Returns true if the endpoint string is safe to send credentials to (HTTPS or localhost).
func isEndpointSecure(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString) else { return false }
    return url.isEndpointSecure
}

// MARK: - LLMClientFactory

/// Creates the appropriate LLMClient based on provider configuration.
enum LLMClientFactory {
    static func makeClient(for config: ModelConfiguration) throws -> any LLMClient {
        switch config.providerType.apiFormat {
        case .openaiCompatible:
            OpenAICompatibleClient(
                endpoint: config.endpoint ?? config.providerType.defaultEndpoint,
                apiKey: config.apiKey,
                modelName: config.modelName ?? ""
            )
        case .anthropicMessages:
            AnthropicClient(
                apiKey: config.apiKey ?? "",
                modelName: config.modelName ?? "claude-sonnet-4-20250514",
                endpoint: config.endpoint ?? "https://api.anthropic.com"
            )
        }
    }
}
