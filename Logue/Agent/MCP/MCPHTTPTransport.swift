import Foundation
import os.log

/// Talking to a server over HTTP.
///
/// Deliberately thin. Every decision that matters — whether the address is one we will talk
/// to, whether the server is allowed to run, what its tools are called, how much they are
/// trusted, and what their output may do — is settled before anything gets here. This only
/// moves bytes, and it is the last piece of #63 for exactly that reason.
struct MCPHTTPTransport: MCPTransport {
    private static let logger = Logger(subsystem: AppConstants.bundleID, category: "MCP")

    /// One session, configured with the timeouts rather than trusting a caller to pass them.
    ///
    /// `timeoutIntervalForResource` as well as `forRequest`: a server that dribbles a byte a
    /// second keeps resetting the request timeout and would otherwise hold the connection
    /// open indefinitely without ever being idle.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = MCPTimeout.call
        configuration.timeoutIntervalForResource = MCPTimeout.call
        // Nothing about a tool call should be served from a cache, and an ephemeral session
        // keeps nothing on disk — this is somebody else's server, and Logue's posture is that
        // it stores as little as it can.
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    func listTools(server: MCPServer) async throws -> [MCPToolDescriptor] {
        let result = try await send(
            MCPWireFormat.listToolsBody(),
            to: server,
            timeout: MCPTimeout.discovery
        )
        return MCPWireFormat.tools(from: result)
    }

    func call(server: MCPServer, tool: String, arguments: [String: Any]) async throws -> String {
        let result = try await send(
            MCPWireFormat.callToolBody(name: tool, arguments: arguments),
            to: server,
            timeout: MCPTimeout.call
        )
        return MCPWireFormat.callText(from: result)
    }

    private func send(
        _ body: Data,
        to server: MCPServer,
        timeout: TimeInterval
    ) async throws -> [String: Any] {
        var request = URLRequest(url: server.endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (stream, response) = try await Self.session.bytes(for: request)
        let data = try await Self.read(stream, declaring: response.expectedContentLength)

        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            // Host only, never the address — the project rule, and it applies to error paths
            // as much as to success ones.
            Self.logger.error(
                "MCP server returned \(http.statusCode) — \(server.endpoint.host ?? "?", privacy: .public)"
            )
            throw MCPWireFormat.WireError.server("HTTP \(http.statusCode)")
        }
        return try MCPWireFormat.result(from: data)
    }

    /// Reads a reply, stopping the moment it exceeds what we are willing to hold.
    ///
    /// `URLSession.data(for:)` buffers the whole body before returning it, so checking the
    /// size afterwards checks a allocation that has already happened — a server could make
    /// Logue hold a hundred megabytes and the bound in `MCPWireFormat` would only stop it
    /// being *parsed*. This is what makes that bound real: the read stops at the cap, so the
    /// most a server can make us hold is the cap itself.
    ///
    /// `expectedContentLength` is a fast reject for a server that declares the size honestly,
    /// and it is only that — a server that lies, or sends no `Content-Length`, is caught by
    /// the running total, which is the check that does not depend on the server telling the
    /// truth.
    private static func read(_ stream: URLSession.AsyncBytes, declaring declared: Int64) async throws -> Data {
        if declared > Int64(MCPWireFormat.maxResponseBytes) {
            throw MCPWireFormat.WireError.tooLarge
        }

        var data = Data()
        data.reserveCapacity(min(Int(max(declared, 0)), MCPWireFormat.maxResponseBytes))
        for try await byte in stream {
            data.append(byte)
            if data.count > MCPWireFormat.maxResponseBytes {
                throw MCPWireFormat.WireError.tooLarge
            }
        }
        return data
    }
}
