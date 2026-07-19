import Foundation
import MLXLMCommon

/// Helpers for building `ToolSpec` dictionaries (MLX tool-calling JSON Schema).
///
/// Keeps tool implementations readable — each tool declares its spec inline via
/// `AgentToolSpec.make(name:description:properties:required:)` instead of a multi-level
/// dictionary literal.
enum AgentToolSpec {
    // MARK: - Spec Construction

    /// Build a full tool spec from name, description, and parameter schema.
    static func make(
        name: String,
        description: String,
        properties: [String: [String: any Sendable]] = [:],
        required: [String] = []
    ) -> ToolSpec {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties as [String: any Sendable],
                    "required": required as [String],
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ]
    }

    // MARK: - Parameter Schema Helpers

    static func stringParam(_ description: String, enumValues: [String]? = nil) -> [String: any Sendable] {
        var param: [String: any Sendable] = [
            "type": "string",
            "description": description,
        ]
        if let enumValues {
            param["enum"] = enumValues
        }
        return param
    }

    static func intParam(_ description: String) -> [String: any Sendable] {
        ["type": "integer", "description": description]
    }

    static func boolParam(_ description: String) -> [String: any Sendable] {
        ["type": "boolean", "description": description]
    }

    static func stringArrayParam(_ description: String) -> [String: any Sendable] {
        [
            "type": "array",
            "description": description,
            "items": ["type": "string"] as [String: any Sendable],
        ]
    }
}
