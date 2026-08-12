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

        let sanitised = rawMessages.compactMap(sanitisedMessage)
        guard !sanitised.isEmpty else { return nil }

        // The app owns the system turn, not the caller — see `sanitisedMessage`.
        let systemTurn: [String: any Sendable] = ["role": "system", "content": LLMEngine.chatSystemPrompt]
        let messages = [systemTurn] + boundedToContextWindow(sanitised)

        // `as? ToolSpec` filtered nothing: `ToolSpec` is `[String: any Sendable]` and `Sendable`
        // is a marker protocol, so the cast is erased at runtime and always succeeds — the
        // compiler said so. Whatever JSON the caller sent went straight into the chat template.
        let rawTools = (body["tools"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
        let tools = rawTools
            .prefix(maxTools)
            .compactMap(sanitisedToolSpec)
        let wantsStream = (body["stream"] as? Bool) ?? true

        return ChatRequest(messages: messages, tools: Array(tools), wantsStream: wantsStream)
    }

    /// Keeps the most recent turns that fit the model's context window, oldest dropped first.
    ///
    /// Every other LLM call in the app validates its input against the context window before
    /// making it; this path did not, so with an 8 MB body cap a caller could hand the tokenizer
    /// an 8 MB prompt on an endpoint any local process can reach. The newest turns are the ones
    /// worth keeping — the question is at the end.
    nonisolated static func boundedToContextWindow(
        _ messages: [[String: any Sendable]]
    ) -> [[String: any Sendable]] {
        let budget = LLMEngine.maxInputChars(
            reservedTokens: AppConstants.BrowserBridge.chatMaxTokens
                + AppConstants.BrowserBridge.systemPromptReservedTokens
        )
        var kept: [[String: any Sendable]] = []
        var used = 0
        for message in messages.reversed() {
            let cost = (message["content"] as? String)?.count ?? 0
            // Always keep the newest turn even if it alone exceeds the budget; it is truncated
            // rather than dropped, because dropping it answers a question nobody asked.
            if kept.isEmpty {
                kept.append(truncatingContent(message, to: budget))
                used = min(cost, budget)
                continue
            }
            guard used + cost <= budget else { break }
            used += cost
            kept.insert(message, at: 0)
        }
        return kept
    }

    nonisolated private static func truncatingContent(
        _ message: [[String: any Sendable]].Element, to limit: Int
    ) -> [String: any Sendable] {
        guard let content = message["content"] as? String, content.count > limit else { return message }
        var truncated = message
        truncated["content"] = String(content.prefix(limit))
        return truncated
    }

    /// Bounds on what a caller may declare. A tool list is a description of the *browser's*
    /// capabilities, so a handful of short entries is the honest shape; anything past this is
    /// either a mistake or an attempt to spend the context window.
    nonisolated static let maxTools = 32
    nonisolated static let maxToolNameCharacters = 64
    nonisolated static let maxToolDescriptionCharacters = 1024
    /// How deep a `parameters` schema may nest before it is refused. JSON Schema for a tool is
    /// shallow in practice; unbounded recursion over caller-supplied JSON is not something to
    /// hand a template.
    nonisolated static let maxToolSchemaDepth = 8

    /// One tool declaration, reduced to the fields a chat template understands.
    ///
    /// Same rule as `sanitisedMessage`, which the doc comment above already claimed applied to
    /// tools and did not: everything here is about to be rendered by a Jinja template, so it is
    /// rebuilt from known keys rather than passed through.
    nonisolated static func sanitisedToolSpec(_ raw: [String: Any]) -> ToolSpec? {
        // OpenAI's shape. Anything else is not a tool declaration this understands.
        guard (raw["type"] as? String) == "function",
              let function = raw["function"] as? [String: Any],
              let name = function["name"] as? String
        else { return nil }

        let cleanName = sanitisedIdentifier(name)
        guard !cleanName.isEmpty else { return nil }

        var spec: [String: any Sendable] = ["name": cleanName]
        if let description = function["description"] as? String {
            spec["description"] = String(description.prefix(maxToolDescriptionCharacters))
        }
        // A schema is arbitrary nested JSON by definition, so it is whitelisted by *type*
        // rather than by key — objects, arrays, strings, numbers and bools, nothing else.
        if let parameters = function["parameters"] as? [String: Any],
           let clean = sanitisedJSONObject(parameters, depth: 0)
        {
            spec["parameters"] = clean
        }

        return ["type": "function", "function": spec]
    }

    /// Strips a name down to what a tool name can be, so it cannot carry template syntax or
    /// newlines into the rendered prompt.
    nonisolated private static func sanitisedIdentifier(_ raw: String) -> String {
        String(raw.prefix(maxToolNameCharacters))
            .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" || $0 == "." }
    }

    /// Rebuilds a JSON object keeping only JSON-representable values, bounded by depth.
    nonisolated private static func sanitisedJSONObject(
        _ raw: [String: Any], depth: Int
    ) -> [String: any Sendable]? {
        guard depth < maxToolSchemaDepth else { return nil }
        var clean: [String: any Sendable] = [:]
        for (key, value) in raw {
            let cleanKey = String(key.prefix(maxToolNameCharacters))
            guard !cleanKey.isEmpty, let cleanValue = sanitisedJSONValue(value, depth: depth) else {
                continue
            }
            clean[cleanKey] = cleanValue
        }
        return clean
    }

    nonisolated private static func sanitisedJSONValue(_ value: Any, depth: Int) -> (any Sendable)? {
        switch value {
        case let string as String:
            String(string.prefix(maxToolDescriptionCharacters))
        case let bool as Bool:
            bool
        case let int as Int:
            int
        case let double as Double:
            double
        case let object as [String: Any]:
            sanitisedJSONObject(object, depth: depth + 1)
        case let array as [Any]:
            array.prefix(maxTools).compactMap { sanitisedJSONValue($0, depth: depth + 1) }
        default:
            // Null and anything unrecognised are dropped rather than guessed at.
            nil
        }
    }

    /// One message, reduced to the fields a chat template understands.
    ///
    /// `system` is deliberately not an accepted role. The bridge supplies the system turn
    /// itself (`LLMEngine.chatSystemPrompt`); letting the caller send one meant whoever was on
    /// the other end of the socket defined the model's instructions rather than the app.
    nonisolated private static func sanitisedMessage(_ raw: [String: Any]) -> [String: any Sendable]? {
        guard let role = raw["role"] as? String,
              ["user", "assistant", "tool"].contains(role)
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
