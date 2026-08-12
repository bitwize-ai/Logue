import Foundation
import OSLog

/// What each endpoint actually answers.
///
/// Kept apart from the socket handling so this file reads as the API and that one reads as the
/// plumbing. Everything here runs on the main actor, because the state it reports — the active
/// model, whether a model is loaded — lives there.
@MainActor
extension BrowserBridgeServer {
    /// The fingerprint the extension checks before it will talk to a port. Without it, any local
    /// process answering on 52452 would be mistaken for Logue.
    static let appIdentifier = "logue-mlx"

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    }

    func handle(
        decision: BrowserBridgeRoute.Decision,
        request: HTTPMessage.Request,
        origin: String?,
        on connection: Connection
    ) async {
        switch decision {
        case .preflight:
            connection.send(
                HTTPMessage.Response(status: 204, headers: [:], body: Data()),
                origin: origin, keepAlive: true
            )

        case .forbiddenOrigin:
            connection.send(
                .error("Only the Logue browser extension can use this.", status: 403),
                origin: nil, keepAlive: false, thenClose: true
            )

        case .forbiddenHost:
            // No ACAO and no keep-alive: whatever name resolved to this port, it is not one this
            // bridge answers for, and a rebinding attempt should not get a reusable connection.
            connection.send(
                .error("This bridge only answers to its own address on this Mac.", status: 403),
                origin: nil, keepAlive: false, thenClose: true
            )

        case .methodNotAllowed:
            connection.send(
                .error("Wrong method for that endpoint.", status: 405),
                origin: origin,
                keepAlive: true
            )

        case let .notImplemented(route):
            connection.send(
                .error(BrowserBridgeRoute.notImplementedMessage(for: route), status: 501),
                origin: origin, keepAlive: true
            )

        case .notFound:
            connection.send(.error("No such endpoint.", status: 404), origin: origin, keepAlive: true)

        case let .serve(known):
            await serve(known, request: request, origin: origin, on: connection)
        }
    }

    private func serve(
        _ route: BrowserBridgeRoute.Known,
        request: HTTPMessage.Request,
        origin: String?,
        on connection: Connection
    ) async {
        switch route {
        case .status:
            await connection.send(.json(statusPayload()), origin: origin, keepAlive: true)

        case .handshake:
            connection.send(.json(handshakePayload()), origin: origin, keepAlive: true)

        case .models:
            connection.send(.json(modelsPayload()), origin: origin, keepAlive: true)

        case .chat, .chatCompletions:
            await serveChat(route, request: request, origin: origin, on: connection)
        }
    }

    // MARK: - Status, handshake, models

    private func statusPayload() async -> [String: Any] {
        let manager = ModelManager.shared
        let ready = await LLMEngine.shared.isReady
        return [
            "app": Self.appIdentifier,
            "status": "ok",
            "modelLoaded": ready,
            "activeModel": manager.activeModel?.displayName ?? NSNull(),
            "version": Self.appVersion,
        ]
    }

    /// The handshake exists because the extension asks for one, not because it secures anything.
    ///
    /// The token it returns is a fresh random string the server does not check on later requests —
    /// there is no authentication here by design. It is worth being blunt about that rather than
    /// letting the ceremony imply a guarantee it does not provide.
    private func handshakePayload() -> [String: Any] {
        [
            "app": Self.appIdentifier,
            "session": UUID().uuidString,
            "port": Int(activePort ?? 0),
            "version": Self.appVersion,
        ]
    }

    private func modelsPayload() -> [String: Any] {
        let manager = ModelManager.shared
        let activeID = manager.activeModelID
        let models = manager.allModels.map { model in
            [
                "id": model.id,
                "name": model.displayName,
                "type": model.type.rawValue,
                "active": model.id == activeID,
            ] as [String: Any]
        }
        return ["models": models]
    }

    // MARK: - Chat

    private func serveChat(
        _ route: BrowserBridgeRoute.Known,
        request: HTTPMessage.Request,
        origin: String?,
        on connection: Connection
    ) async {
        guard await LLMEngine.shared.isReady else {
            connection.send(
                .error("No model is loaded in Logue. Open Logue and choose one.", status: 503),
                origin: origin, keepAlive: true
            )
            return
        }

        let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
        guard let prompt = Self.prompt(from: body, route: route), !prompt.isEmpty else {
            connection.send(.error("No message to answer.", status: 400), origin: origin, keepAlive: true)
            return
        }

        // A request carrying tools takes the tool path, whichever endpoint it arrived on. The
        // model may answer in text or ask to call something, and only that path can stream both.
        if let toolRequest = Self.chatRequest(from: body), toolRequest.usesTools {
            await streamWithTools(toolRequest, origin: origin, on: connection)
            return
        }

        let wantsStream = (body["stream"] as? Bool) ?? (route == .chatCompletions)
        if wantsStream {
            await streamChat(prompt: prompt, origin: origin, on: connection)
        } else {
            await completeChat(prompt: prompt, origin: origin, on: connection)
        }
    }

    /// Pulls the user's text out of either request shape.
    ///
    /// `/v1/logue/chat` sends `{ message, context }`; `/v1/chat/completions` sends OpenAI's
    /// `{ messages: [...] }`. Both end up as one prompt.
    ///
    /// Page content arrives as `context` and is wrapped in a delimiter before it reaches the
    /// model, the same rule every other prompt in the app follows: it is somebody else's web page,
    /// so it is data, not instructions.
    nonisolated static func prompt(from body: [String: Any], route: BrowserBridgeRoute.Known) -> String? {
        if route == .chatCompletions {
            guard let messages = body["messages"] as? [[String: Any]] else { return nil }
            // Every turn is wrapped and labelled by attribute rather than joined as
            // "role: content". Joined text let a message containing a literal "system: …" render
            // as what looks like a role turn, which is the whole reason the app's rule is to
            // delimit rather than concatenate. `system` is not accepted from a caller at all —
            // the bridge supplies that turn.
            let rendered = messages.compactMap { message -> String? in
                guard let role = message["role"] as? String,
                      ["user", "assistant", "tool"].contains(role),
                      let content = message["content"] as? String, !content.isEmpty
                else { return nil }
                return "<turn role=\"\(role)\">\n\(escapingDelimiters(content, limit: maxMessageCharacters))\n</turn>"
            }
            guard !rendered.isEmpty else { return nil }
            return String(rendered.joined(separator: "\n\n").suffix(maxPromptCharacters))
        }

        guard let message = body["message"] as? String else { return nil }
        // Bounded like everything else here: `message` was limited only by the 8 MB body cap.
        let question = escapingDelimiters(message, limit: maxMessageCharacters)
        guard let context = body["context"] as? String, !context.isEmpty else { return question }

        let trimmed = escapingDelimiters(context, limit: maxContextCharacters)
        return """
        <page>
        \(trimmed)
        </page>

        \(question)
        """
    }

    /// Truncates, then neutralises anything that would close a delimiter this file opened.
    ///
    /// Wrapping alone is half the rule: a page containing `</page>` followed by instructions
    /// closed the block and went on speaking as the operator. The closing bracket is replaced
    /// rather than the whole tag stripped, so the text still reads as what the page said.
    /// Control characters go too — the same treatment every other prompt in the app gives
    /// user-supplied strings.
    nonisolated static func escapingDelimiters(_ raw: String, limit: Int) -> String {
        String(raw.prefix(limit))
            .replacingOccurrences(of: "</page>", with: "<\u{2044}page>")
            .replacingOccurrences(of: "</turn>", with: "<\u{2044}turn>")
            .filter(isPrintable)
    }

    /// Newlines and tabs survive — page text is unreadable without them. Everything else below
    /// the printable range, and DEL, does not.
    nonisolated private static func isPrintable(_ character: Character) -> Bool {
        guard let ascii = character.asciiValue else { return true }
        if ascii == 0x0A || ascii == 0x09 { return true }
        return ascii >= 0x20 && ascii != 0x7F
    }

    /// How much page content is passed through. The engine truncates to the context window on its
    /// own, but a whole page arriving as one string is worth bounding before it gets that far.
    nonisolated static let maxContextCharacters = 12000

    /// Cap on a single message. `message` previously had none at all.
    nonisolated static let maxMessageCharacters = 12000

    /// Cap on the whole rendered prompt, so a caller cannot spend the context window by sending
    /// many messages that are each individually within bounds.
    nonisolated static let maxPromptCharacters = 48000

    /// The non-streaming answer.
    ///
    /// A client that hangs up mid-generation is honoured here the same way it is on the
    /// streaming paths, but by cancellation rather than by a liveness check: there is no loop to
    /// check in. `Connection.close()` cancels this connection's response chain, `complete()`
    /// unwinds through its own `withTaskCancellationHandler`, and the inference gate is released
    /// instead of being held for a full `chatMaxTokens` generation nobody will read. This is the
    /// default path for `/v1/logue/chat`, which is non-streaming unless `stream` is set.
    private func completeChat(prompt: String, origin: String?, on connection: Connection) async {
        do {
            let answer = try await LLMEngine.shared.complete(
                system: LLMEngine.chatSystemPrompt,
                prompt: prompt,
                maxTokens: AppConstants.BrowserBridge.chatMaxTokens
            )
            connection.send(.json(["text": answer]), origin: origin, keepAlive: true)
        } catch {
            logger.error("Browser bridge chat failed: \(error.localizedDescription, privacy: .public)")
            connection.send(
                .error("Logue could not answer that.", status: 500), origin: origin, keepAlive: true
            )
        }
    }

    /// Streams the answer as Server-Sent Events, in the shape the extension's parser expects:
    /// `data:` frames carrying an OpenAI-style delta, then `data: [DONE]`.
    private func streamChat(prompt: String, origin: String?, on connection: Connection) async {
        connection.send(.eventStream(), origin: origin, keepAlive: false, streaming: true)

        let identifier = "chatcmpl-\(UUID().uuidString)"
        do {
            let stream = try await LLMEngine.shared.completeStream(
                system: LLMEngine.chatSystemPrompt,
                prompt: prompt,
                maxTokens: AppConstants.BrowserBridge.chatMaxTokens
            )
            for try await token in stream {
                // Stop pulling tokens the moment the client goes away. Writing into a dead
                // connection fails quietly, so without this a user pressing stop — or closing the
                // tab — left the model generating to nobody and holding the inference gate.
                guard connection.isLive else {
                    logger.info("Browser bridge stopped a stream: the client went away")
                    return
                }
                guard !token.isEmpty else { continue }
                connection.write(HTTPMessage.eventFrame(Self.deltaFrame(identifier: identifier, token: token)))
            }
            connection.write(HTTPMessage.eventFrame(Self.finishFrame(identifier: identifier)))
        } catch {
            logger.error("Browser bridge stream failed: \(error.localizedDescription, privacy: .public)")
            // Reported inside the stream, because the head has already gone out and the status
            // code can no longer say anything.
            connection.write(HTTPMessage.eventFrame(Self.errorFrame(message: "Logue could not answer that.")))
        }
        connection.write(Data("data: [DONE]\n\n".utf8), thenClose: true)
    }

    nonisolated static func deltaFrame(identifier: String, token: String) -> String {
        encode([
            "id": identifier,
            "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": ["content": token], "finish_reason": NSNull()]],
        ])
    }

    nonisolated static func finishFrame(identifier: String, reason: String = "stop") -> String {
        encode([
            "id": identifier,
            "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": [:] as [String: Any], "finish_reason": reason]],
        ])
    }

    nonisolated static func errorFrame(message: String) -> String {
        encode(["error": message, "code": 500])
    }

    nonisolated static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
