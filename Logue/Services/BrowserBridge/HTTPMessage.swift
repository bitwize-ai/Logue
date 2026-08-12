import Foundation

/// The slice of HTTP/1.1 the browser bridge needs, and nothing more.
///
/// Hand-rolled rather than pulled in as a dependency because the surface is tiny and entirely
/// under our control: one client, on loopback, speaking `fetch`. A general server would be more
/// code to audit for a feature whose whole point is that it stays on this machine.
///
/// Everything here is pure — bytes in, values out — so the parsing rules can be tested without
/// opening a socket.
enum HTTPMessage {
    /// A parsed request line, headers and body.
    struct Request: Equatable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data

        /// Header lookup is case-insensitive: HTTP field names are, and `fetch` does not promise
        /// a particular casing.
        func header(_ name: String) -> String? {
            headers[name.lowercased()]
        }

        var bodyText: String {
            String(data: body, encoding: .utf8) ?? ""
        }
    }

    /// Why a request could not be parsed. Distinguished because "we have not read enough yet" is
    /// not an error — it is the normal state of a connection mid-message.
    enum ParseError: Error, Equatable {
        /// The head is not complete yet. Read more and try again.
        case incomplete
        /// The head is complete but malformed. The connection cannot recover.
        case malformed
        /// Well-formed, but framed a way this server does not implement — `Transfer-Encoding`.
        /// Answered `501` rather than `400`, because the request is not the client's mistake.
        case unsupportedFraming
    }

    /// Largest request we will hold in memory.
    ///
    /// A local client sending an entire page as chat context is the intended case, so this is
    /// generous — but unbounded is not an option when anything on the machine can connect.
    static let maxBodyBytes = 8 * 1024 * 1024

    // MARK: - Parsing

    /// Parses one request from the head of `buffer`.
    ///
    /// Returns the request and how many bytes it consumed, so the caller can keep the remainder
    /// for the next one — `fetch` reuses connections, and a keep-alive connection carries several
    /// requests back to back.
    static func parseRequest(from buffer: Data) throws -> (request: Request, consumed: Int) {
        guard let headEnd = rangeOfHeadTerminator(in: buffer) else {
            // Not a failure: the rest of the head may still be in flight.
            guard buffer.count <= maxBodyBytes else { throw ParseError.malformed }
            throw ParseError.incomplete
        }

        let headData = buffer[buffer.startIndex ..< headEnd.lowerBound]
        guard let head = String(data: headData, encoding: .utf8) else { throw ParseError.malformed }

        var lines = head.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { throw ParseError.malformed }
        lines.removeFirst()

        let parts = requestLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { throw ParseError.malformed }
        let method = String(parts[0]).uppercased()
        let path = String(parts[1])
        guard !method.isEmpty, path.hasPrefix("/") else { throw ParseError.malformed }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            // An obs-fold continuation — a line starting with SP or HTAB — belongs to the header
            // above it. This parser has no notion of that, so a folded line containing a colon
            // was smuggled in as a header of its own. Obsolete since RFC 7230; refuse it.
            guard let first = line.first, first != " ", first != "\t" else { throw ParseError.malformed }
            guard let colon = line.firstIndex(of: ":") else { throw ParseError.malformed }
            let name = line[line.startIndex ..< colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { throw ParseError.malformed }
            // Last-wins on a repeated `Content-Length` is how a framing disagreement becomes a
            // smuggled request. Two of them is a malformed message, not a preference.
            guard headers[name] == nil || name != "content-length" else { throw ParseError.malformed }
            headers[name] = value
        }

        // Not supported, and silence was the dangerous answer: a chunked body was read as length
        // zero, leaving the chunk data in the buffer to be parsed as the *next* request on a
        // connection that deliberately supports pipelining.
        guard headers["transfer-encoding"] == nil else { throw ParseError.unsupportedFraming }

        // Absent means no body. Present-but-unparseable is a framing disagreement, and `?? 0`
        // resolved it in the sender's favour.
        let declaredLength: Int
        if let raw = headers["content-length"] {
            guard let parsed = Int(raw) else { throw ParseError.malformed }
            declaredLength = parsed
        } else {
            declaredLength = 0
        }
        guard declaredLength >= 0, declaredLength <= maxBodyBytes else { throw ParseError.malformed }

        let bodyStart = headEnd.upperBound
        let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
        guard available >= declaredLength else { throw ParseError.incomplete }

        let bodyEnd = buffer.index(bodyStart, offsetBy: declaredLength)
        let body = Data(buffer[bodyStart ..< bodyEnd])
        let consumed = buffer.distance(from: buffer.startIndex, to: bodyEnd)

        return (Request(method: method, path: path, headers: headers, body: body), consumed)
    }

    /// The blank line separating head from body. Only `\r\n\r\n` — a bare `\n\n` is not HTTP, and
    /// accepting it would mean disagreeing with the client about where the body starts.
    private static func rangeOfHeadTerminator(in buffer: Data) -> Range<Data.Index>? {
        let terminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        return buffer.range(of: terminator)
    }

    /// The path with any query string removed. Routing matches on the path alone.
    static func route(from path: String) -> String {
        guard let separator = path.firstIndex(of: "?") else { return path }
        return String(path[path.startIndex ..< separator])
    }

    // MARK: - Responses

    /// A response ready to write. `body` is already encoded.
    struct Response {
        var status: Int
        var headers: [String: String]
        var body: Data

        static func json(_ object: Any, status: Int = 200) -> Response {
            let data = (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8)
            return Response(
                status: status,
                headers: ["Content-Type": "application/json; charset=utf-8"],
                body: data
            )
        }

        /// The error shape the extension expects: `{ "error": …, "code": … }`.
        static func error(_ message: String, status: Int) -> Response {
            json(["error": message, "code": status], status: status)
        }

        /// Headers only, for the start of a Server-Sent Events stream.
        static func eventStream() -> Response {
            Response(
                status: 200,
                headers: [
                    "Content-Type": "text/event-stream; charset=utf-8",
                    // A proxy is not in the picture on loopback, but a browser will still buffer a
                    // stream it thinks might be compressible.
                    "Cache-Control": "no-cache",
                    "X-Accel-Buffering": "no",
                ],
                body: Data()
            )
        }
    }

    private static let reasonPhrases: [Int: String] = [
        200: "OK", 204: "No Content", 400: "Bad Request", 403: "Forbidden",
        404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large",
        500: "Internal Server Error", 501: "Not Implemented", 503: "Service Unavailable",
    ]

    /// Serialises a response head plus body.
    ///
    /// `allowedOrigin` is echoed back rather than answered with `*`: the caller has already
    /// decided the origin is acceptable, and naming it keeps the answer specific to that one
    /// caller instead of opening the endpoint to every page on the machine.
    static func serialise(
        _ response: Response, allowedOrigin: String?, keepAlive: Bool, streaming: Bool = false
    ) -> Data {
        let reason = reasonPhrases[response.status] ?? "OK"
        var head = "HTTP/1.1 \(response.status) \(reason)\r\n"

        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            head += "\(name): \(value)\r\n"
        }
        if let allowedOrigin {
            head += "Access-Control-Allow-Origin: \(allowedOrigin)\r\n"
            head += "Access-Control-Allow-Headers: Content-Type, X-Logue-Session\r\n"
            head += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
            head += "Vary: Origin\r\n"
        }
        // A stream has no length to declare, so the connection closing is what ends it. Every
        // other response declares one, or the client waits for bytes that never come.
        if streaming {
            head += "Connection: close\r\n"
        } else {
            head += "Content-Length: \(response.body.count)\r\n"
            head += "Connection: \(keepAlive ? "keep-alive" : "close")\r\n"
        }
        head += "\r\n"

        var data = Data(head.utf8)
        data.append(response.body)
        return data
    }

    /// One `data:` frame of a Server-Sent Events stream.
    static func eventFrame(_ payload: String) -> Data {
        Data("data: \(payload)\n\n".utf8)
    }
}
