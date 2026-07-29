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
            let rendered = messages.compactMap { message -> String? in
                guard let role = message["role"] as? String,
                      let content = message["content"] as? String, !content.isEmpty
                else { return nil }
                return "\(role): \(content)"
            }
            return rendered.isEmpty ? nil : rendered.joined(separator: "\n\n")
        }

        guard let message = body["message"] as? String else { return nil }
        guard let context = body["context"] as? String, !context.isEmpty else { return message }

        let trimmed = String(context.prefix(Self.maxContextCharacters))
        return """
        <page>
        \(trimmed)
        </page>

        \(message)
        """
    }

    /// How much page content is passed through. The engine truncates to the context window on its
    /// own, but a whole page arriving as one string is worth bounding before it gets that far.
    nonisolated static let maxContextCharacters = 12000

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

    private static func deltaFrame(identifier: String, token: String) -> String {
        encode([
            "id": identifier,
            "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": ["content": token], "finish_reason": NSNull()]],
        ])
    }

    private static func finishFrame(identifier: String) -> String {
        encode([
            "id": identifier,
            "object": "chat.completion.chunk",
            "choices": [["index": 0, "delta": [:] as [String: Any], "finish_reason": "stop"]],
        ])
    }

    private static func errorFrame(message: String) -> String {
        encode(["error": message, "code": 500])
    }

    private static func encode(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }
}
