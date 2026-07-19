import Foundation
import SwiftUI

// MARK: - ModelType

enum ModelType: String, Codable, CaseIterable, Identifiable {
    case mlx = "MLX (On-Device)"
    case api = "Cloud / API"

    var id: String {
        rawValue
    }

    /// Backward compatibility: decode old "OpenAI API" value
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw {
        case "OpenAI API": self = .api
        default: self = ModelType(rawValue: raw) ?? .api
        }
    }
}

// MARK: - ConnectionStatus

enum ConnectionStatus: Equatable {
    case idle
    case checking
    case connected
    case error(String)

    var dotColor: Color {
        switch self {
        case .idle: AppThemeConstants.mutedText
        case .checking: AppThemeConstants.warning
        case .connected: AppThemeConstants.success
        case .error: AppThemeConstants.error
        }
    }

    var label: String {
        switch self {
        case .idle: "Not tested"
        case .checking: "Checking…"
        case .connected: "Connected"
        case let .error(msg): "Error: \(msg)"
        }
    }
}

// MARK: - APIFormat

/// The wire format used by a provider's API.
enum APIFormat {
    case openaiCompatible
    case anthropicMessages
}

// MARK: - APIProviderType

enum APIProviderType: String, Codable, CaseIterable, Identifiable {
    case openai
    case anthropic
    case openRouter
    case ollama
    case lmStudio
    case llamacpp
    case openaiCompatible

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .openai: "OpenAI"
        case .anthropic: "Anthropic"
        case .openRouter: "OpenRouter"
        case .ollama: "Ollama"
        case .lmStudio: "LM Studio"
        case .llamacpp: "llama.cpp"
        case .openaiCompatible: "OpenAI-Compatible"
        }
    }

    var defaultEndpoint: String {
        switch self {
        case .openai: "https://api.openai.com/v1"
        case .anthropic: "https://api.anthropic.com"
        case .openRouter: "https://openrouter.ai/api/v1"
        case .ollama: "http://localhost:11434/v1"
        case .lmStudio: "http://localhost:1234/v1"
        case .llamacpp: "http://localhost:8080/v1"
        case .openaiCompatible: ""
        }
    }

    var icon: String {
        switch self {
        case .openai: "brain.head.profile"
        case .anthropic: "wand.and.rays"
        case .openRouter: "arrow.triangle.branch"
        case .ollama: "hare"
        case .lmStudio: "wand.and.stars"
        case .llamacpp: "terminal"
        case .openaiCompatible: "globe"
        }
    }

    var requiresAuthByDefault: Bool {
        switch self {
        case .openai, .anthropic, .openRouter: true
        default: false
        }
    }

    var apiFormat: APIFormat {
        switch self {
        case .anthropic: .anthropicMessages
        default: .openaiCompatible
        }
    }

    /// Providers shown in the "Connect" picker (excludes legacy local-only types).
    static var connectableProviders: [APIProviderType] {
        [.openai, .anthropic, .openRouter, .ollama, .openaiCompatible]
    }
}

// MARK: - ModelConfiguration

struct ModelConfiguration: Identifiable, Codable {
    let id: String
    let type: ModelType
    let displayName: String
    let description: String

    // MLX-specific
    let hfRepoID: String?
    let sizeGB: Double?
    let minRAMGB: Double?

    // API-specific
    let endpoint: String?
    let apiKey: String?
    let modelName: String?
    let requiresAuth: Bool

    /// Provider identification (stored, not computed)
    let providerType: APIProviderType

    var isRecommended: Bool

    init(
        id: String,
        type: ModelType,
        displayName: String,
        description: String,
        hfRepoID: String? = nil,
        sizeGB: Double? = nil,
        minRAMGB: Double? = nil,
        endpoint: String? = nil,
        apiKey: String? = nil,
        modelName: String? = nil,
        requiresAuth: Bool = false,
        providerType: APIProviderType = .openaiCompatible,
        isRecommended: Bool = false
    ) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.description = description
        self.hfRepoID = hfRepoID
        self.sizeGB = sizeGB
        self.minRAMGB = minRAMGB
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.modelName = modelName
        self.requiresAuth = requiresAuth
        self.providerType = providerType
        self.isRecommended = isRecommended
    }

    // MARK: - Codable (backward compatibility)

    enum CodingKeys: String, CodingKey {
        case id, type, displayName, description
        case hfRepoID, sizeGB, minRAMGB
        case endpoint, apiKey, modelName, requiresAuth
        case providerType
        case isRecommended
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(ModelType.self, forKey: .type)
        displayName = try container.decode(String.self, forKey: .displayName)
        description = try container.decode(String.self, forKey: .description)
        hfRepoID = try container.decodeIfPresent(String.self, forKey: .hfRepoID)
        sizeGB = try container.decodeIfPresent(Double.self, forKey: .sizeGB)
        minRAMGB = try container.decodeIfPresent(Double.self, forKey: .minRAMGB)
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint)
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey)
        modelName = try container.decodeIfPresent(String.self, forKey: .modelName)
        requiresAuth = try container.decodeIfPresent(Bool.self, forKey: .requiresAuth) ?? false
        isRecommended = try container.decodeIfPresent(Bool.self, forKey: .isRecommended) ?? false

        // Backward compat: old configs lack providerType — infer from endpoint
        if let stored = try? container.decode(APIProviderType.self, forKey: .providerType) {
            providerType = stored
        } else {
            // Legacy heuristic
            let ep = endpoint ?? ""
            if ep.contains("11434") {
                providerType = .ollama
            } else if ep.contains("1234") {
                providerType = .lmStudio
            } else if ep.contains("8080") {
                providerType = .llamacpp
            } else {
                providerType = .openaiCompatible
            }
        }
    }

    /// Custom encode that strips secrets — they are stored in Keychain, not UserDefaults.
    /// This prevents accidental serialization of credentials in logs, crash reports, or backups.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(description, forKey: .description)
        try container.encodeIfPresent(hfRepoID, forKey: .hfRepoID)
        try container.encodeIfPresent(sizeGB, forKey: .sizeGB)
        try container.encodeIfPresent(minRAMGB, forKey: .minRAMGB)
        try container.encodeIfPresent(endpoint, forKey: .endpoint)
        // Deliberately omit apiKey — stored in Keychain, never serialized
        try container.encodeIfPresent(modelName, forKey: .modelName)
        try container.encode(requiresAuth, forKey: .requiresAuth)
        try container.encode(providerType, forKey: .providerType)
        try container.encode(isRecommended, forKey: .isRecommended)
    }
}

// MARK: - Preset Catalog

extension ModelConfiguration {
    /// Built-in MLX models
    static let mlxPresets: [ModelConfiguration] = [
        ModelConfiguration(
            id: "mlx-josie-1.1-4b",
            type: .mlx,
            displayName: "JOSIE 1.1 4B",
            description: "JOSIE 1.1 Instruct (4-bit). Best quality for writing, grammar, and analysis tasks. Recommended.",
            hfRepoID: "mlx-community/JOSIE-1.1-4B-Instruct-4bit",
            sizeGB: 2.5,
            minRAMGB: 6,
            isRecommended: true
        ),
        ModelConfiguration(
            id: "mlx-qwen3-4b-4bit",
            type: .mlx,
            displayName: "Qwen3 4B Instruct",
            description: "Qwen's 4B instruct model (4-bit). Great quality at half the size — good for Macs with 8 GB+ RAM.",
            hfRepoID: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
            sizeGB: 2.26,
            minRAMGB: 8
        ),
    ]

    /// Built-in OpenAI-compatible endpoint presets
    static let apiPresets: [ModelConfiguration] = []

    static var allPresets: [ModelConfiguration] {
        mlxPresets
    }

    static var defaultPreset: ModelConfiguration {
        mlxPresets.first { $0.id == "mlx-josie-1.1-4b" } ?? mlxPresets[0]
    }

    /// The model auto-downloaded during onboarding. No user choice exposed.
    static var onboardingModel: ModelConfiguration {
        mlxPresets.first { $0.id == "mlx-josie-1.1-4b" } ?? mlxPresets[0]
    }

    // MARK: - Custom MLX Helpers

    /// Parses a HuggingFace URL or bare repo ID into an mlx-community repo ID.
    ///
    /// Accepts:
    ///   - `https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit`
    ///   - `huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit`
    ///   - `mlx-community/Qwen3-4B-Instruct-2507-4bit`
    ///
    /// Returns `nil` if the input is invalid or not an mlx-community repo.
    static func parseMLXRepoID(from input: String) -> String? {
        let trimmed = input
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Extract path after huggingface.co/ if present
        let path: String
        if let range = trimmed.range(of: "huggingface.co/") {
            path = String(trimmed[range.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        } else if !trimmed.contains("://") {
            // Bare repo ID like "mlx-community/Qwen3-4B-Instruct-2507-4bit"
            path = trimmed
        } else {
            return nil
        }

        let components = path.split(separator: "/", maxSplits: 2).map(String.init)
        guard components.count == 2,
              components[0] == "mlx-community",
              !components[1].isEmpty
        else { return nil }

        return "\(components[0])/\(components[1])"
    }

    /// Creates a `ModelConfiguration` for a user-added MLX model from HuggingFace.
    static func customMLX(repoID: String, sizeGB: Double) -> ModelConfiguration {
        let repoName = repoID.split(separator: "/").last.map(String.init) ?? repoID
        return ModelConfiguration(
            id: "custom-mlx-\(repoID)",
            type: .mlx,
            displayName: repoName,
            description: "Custom model from mlx-community.",
            hfRepoID: repoID,
            sizeGB: sizeGB,
            minRAMGB: max(4, (sizeGB * 1.5).rounded(.up))
        )
    }
}
