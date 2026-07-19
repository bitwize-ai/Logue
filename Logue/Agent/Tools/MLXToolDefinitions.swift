import Foundation
import MLXLMCommon

/// Aggregator for the agent tool registry:
/// - `buildToolSpecs()` collects `spec` from each registered tool (no duplication, no drift)
/// - `dispatch(_:)` looks up the tool by name and executes it
///
/// Each tool owns its own `ToolSpec` via the `AgentTool.spec` requirement, which keeps schema
/// and implementation co-located and eliminates the old "register the tool, forget the spec" bug.
enum MLXToolDefinitions {
    /// Builds all tool specs from the currently registered agent tools.
    @MainActor
    static func buildToolSpecs() -> [ToolSpec] {
        AgentCoordinator.shared.registeredTools.map(\.spec)
    }

    /// Dispatches a `ToolCall` from the model to the matching `AgentTool` and returns the result.
    static func dispatch(_ toolCall: ToolCall) async -> (output: String, isError: Bool) {
        let name = toolCall.function.name
        let args = toolCall.function.arguments.mapValues { $0.anyValue }

        let tool = await MainActor.run {
            AgentCoordinator.shared.registeredTools.first(where: { $0.name == name })
        }
        guard let tool else {
            return (output: "Unknown tool: \(name)", isError: true)
        }

        do {
            let output = try await tool.execute(arguments: args)
            return (output: output, isError: false)
        } catch {
            return (output: "Error: \(error.localizedDescription)", isError: true)
        }
    }
}

// MARK: - JSONValue Helpers

extension JSONValue {
    /// Converts a JSONValue to its plain Swift representation for passing to AgentTool.execute().
    var anyValue: Any {
        switch self {
        case let .string(str): str
        case let .int(num): num
        case let .double(dbl): dbl
        case let .bool(flag): flag
        case let .array(arr): arr.map(\.anyValue)
        case let .object(obj): obj.mapValues(\.anyValue)
        case .null: NSNull()
        }
    }
}
