import Foundation
import MLXLMCommon
import OSLog

/// Tool calling over the bridge.
///
/// The loop deliberately does **not** run here. The tools the browser offers act on the page the
/// user is looking at, and this process cannot see that page — the extension can. So the model's
/// request to call a tool is streamed back as the end of the turn, the extension runs it against
/// the live tab, and sends the result in the next request. That keeps a plain request/response
/// channel sufficient: nothing here has to call back into the browser.
///
/// The wire format is OpenAI's, because the extension already speaks it and inventing a private
/// shape for a well-known exchange buys nothing.
@MainActor
extension BrowserBridgeServer {
    /// A chat turn as it arrived over the wire.
    struct ChatRequest {
        let messages: [[String: any Sendable]]
        let tools: [ToolSpec]
        let wantsStream: Bool

        var usesTools: Bool {
            !tools.isEmpty
        }
    }

    /// Reads the OpenAI-shaped body, keeping only the parts the model can act on.
    ///
    /// Unknown keys are dropped rather than forwarded: everything here is about to be handed to a
    /// chat template, and passing through whatever a caller sent is how a template ends up
    /// rendering something nobody intended.
    nonisolated static func chatRequest(from body: [String: Any]) -> ChatRequest? {
        guard let rawMessages = body["messages"] as? [[String: Any]] else { return nil }

        let messages = rawMessages.compactMap(sanitisedMessage)
        guard !messages.isEmpty else { return nil }

        let tools = (body["tools"] as? [[String: Any]] ?? [])
            .compactMap { $0 as? ToolSpec }
        let wantsStream = (body["stream"] as? Bool) ?? true

        return ChatRequest(messages: messages, tools: tools, wantsStream: wantsStream)
    }

    /// One message, reduced to the fields a chat template understands.
    nonisolated private static func sanitisedMessage(_ raw: [String: Any]) -> [String: any Sendable]? {
        guard let role = raw["role"] as? String,
              ["system", "user", "assistant", "tool"].contains(role)
        else { return nil }

        var message: [String: any Sendable] = ["role": role]

        if let content = raw["content"] as? String {
            message["content"] = content
        }
        // A tool result has to carry the id it answers, or the model cannot pair it with what it
        // asked for.
        if role == "tool", let id = raw["tool_call_id"] as? String {
            message["tool_call_id"] = id
        }
        if role == "assistant", let calls = raw["tool_calls"] as? [[String: Any]] {
            let sanitised = calls.compactMap(sanitisedToolCall)
            if !sanitised.isEmpty {
                message["tool_calls"] = sanitised
            }
        }

        // An assistant turn that is nothing but tool calls has no content, which is legitimate.
        guard message["content"] != nil || message["tool_calls"] != nil else { return nil }
        return message
    }

    nonisolated private static func sanitisedToolCall(_ raw: [String: Any]) -> [String: any Sendable]? {
        guard let function = raw["function"] as? [String: Any],
              let name = function["name"] as? String
        else { return nil }

        let arguments = function["arguments"] as? String ?? "{}"
        return [
            "id": raw["id"] as? String ?? UUID().uuidString,
            "type": "function",
            "function": ["name": name, "arguments": arguments] as [String: any Sendable],
        ]
    }

    // MARK: - Serving

    /// Streams a turn that may end in text or in a request to call a tool.
    func streamWithTools(
        _ request: ChatRequest, origin: String?, on connection: Connection
    ) async {
        connection.send(.eventStream(), origin: origin, keepAlive: false, streaming: true)

        let identifier = "chatcmpl-\(UUID().uuidString)"
        var sawToolCall = false

        do {
            let stream = await LLMEngine.shared.completeWithTools(
                messages: request.messages,
                tools: request.tools,
                maxTokens: AppConstants.BrowserBridge.chatMaxTokens
            )

            for try await generation in stream {
                // The same disconnect check the plain stream makes: a browser that hung up should
                // not leave the model generating for nobody.
                guard connection.isLive else {
                    logger.info("Browser bridge stopped a tool stream: the client went away")
                    return
                }

                switch generation {
                case let .chunk(text) where !text.isEmpty:
                    connection.write(HTTPMessage.eventFrame(
                        Self.deltaFrame(identifier: identifier, token: text)
                    ))
                case let .toolCall(call):
                    sawToolCall = true
                    connection.write(HTTPMessage.eventFrame(
                        Self.toolCallFrame(identifier: identifier, call: call)
                    ))
                default:
                    break
                }
            }

            connection.write(HTTPMessage.eventFrame(Self.finishFrame(
                identifier: identifier, reason: sawToolCall ? "tool_calls" : "stop"
            )))
        } catch {
            logger.error("Browser bridge tool stream failed: \(error.localizedDescription, privacy: .public)")
            connection.write(HTTPMessage.eventFrame(Self.errorFrame(
                message: "Logue could not answer that."
            )))
        }
        connection.write(Data("data: [DONE]\n\n".utf8), thenClose: true)
    }

    /// A tool call in OpenAI's streaming shape.
    ///
    /// Arguments go back as a JSON *string*, which is what that format specifies and what the
    /// extension will parse — the model hands them over already decoded, so they are re-encoded.
    nonisolated static func toolCallFrame(identifier: String, call: ToolCall) -> String {
        let arguments = call.function.arguments.mapValues { $0.anyValue }
        let encoded = (try? JSONSerialization.data(withJSONObject: arguments))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"

        return encode([
            "id": identifier,
            "object": "chat.completion.chunk",
            "choices": [[
                "index": 0,
                "delta": ["tool_calls": [[
                    "index": 0,
                    "id": "call_\(UUID().uuidString.prefix(8))",
                    "type": "function",
                    "function": ["name": call.function.name, "arguments": encoded],
                ]]],
                "finish_reason": NSNull(),
            ]],
        ])
    }
}
