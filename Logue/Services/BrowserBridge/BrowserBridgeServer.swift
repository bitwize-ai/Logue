import Foundation
import Network
import os
import OSLog

/// A loopback HTTP server that lets the Logue browser extension use this Mac's models.
///
/// The privacy story is the whole design. It binds to `127.0.0.1` only — not `0.0.0.0` — so
/// nothing off this machine can reach it, and it is **off until the user turns it on** in
/// Settings, because a listening socket is not something to open on everyone's behalf. Nothing it
/// serves leaves the Mac: the extension sends text in, the local model answers, the answer goes
/// back down the same loopback connection.
///
/// There is deliberately no authentication. The user asked for it to just work, and on loopback
/// the meaningful boundary is the browser's own: it sets `Origin` itself and refuses to hand a
/// response to a page that is not the extension. What that does *not* stop is another program on
/// the same Mac — which is why this is opt-in and why the port is named plainly in Settings.
@MainActor
@Observable
final class BrowserBridgeServer {
    static let shared = BrowserBridgeServer()

    /// Extension-visible: +Handlers
    let logger = Logger(subsystem: AppConstants.bundleID, category: "BrowserBridge")

    /// The port currently accepting connections, or `nil` when nothing is listening.
    private(set) var activePort: UInt16?

    /// The last failure, for Settings to show rather than leaving a toggle that silently did
    /// nothing.
    private(set) var lastError: String?

    var isRunning: Bool {
        activePort != nil
    }

    @ObservationIgnored private var listener: NWListener?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var connections: [ObjectIdentifier: Connection] = [:]

    /// Connection callbacks arrive here, off the main actor, and hop over for anything they touch.
    @ObservationIgnored private let queue = DispatchQueue(
        label: "com.bitwize.logue.browser-bridge", qos: .userInitiated
    )

    private init() {}

    // MARK: - Lifecycle

    /// Starts listening, trying each candidate port in turn.
    ///
    /// More than one port because the first is a guess about what else is on the machine, and a
    /// bridge that fails because some unrelated process took 52452 would be a mystery to the user.
    /// The extension scans the same list.
    func start() {
        guard listener == nil, startTask == nil else { return }
        lastError = nil

        startTask = Task { [weak self] in
            await self?.startFirstFreePort()
            await MainActor.run { self?.startTask = nil }
        }
    }

    /// Tries each candidate port, waiting for each to actually bind before moving on.
    ///
    /// The waiting is the point. `NWListener` reports a port collision *asynchronously*, through
    /// its state handler — the initialiser and `start()` both succeed regardless. Treating those
    /// as success meant the server reported itself listening on a port it had failed to take, and
    /// the failure arrived moments later and quietly stopped it again.
    private func startFirstFreePort() async {
        for port in AppConstants.BrowserBridge.candidatePorts {
            do {
                try await listen(on: port)
                // The user can switch the bridge off while a bind is in flight. `stop()` runs
                // before `self.listener` is assigned, so it has nothing to cancel — and without
                // this the cancelled task would carry on and re-arm a server the user just
                // turned off, holding a socket `stop()` can no longer reach.
                guard !Task.isCancelled else {
                    listener?.cancel()
                    listener = nil
                    return
                }
                activePort = port
                lastError = nil
                logger.info("Browser bridge listening on \(port, privacy: .public)")
                return
            } catch {
                logger.warning(
                    "Browser bridge could not take port \(port, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }

        let ports = AppConstants.BrowserBridge.candidatePorts.map(String.init).joined(separator: ", ")
        lastError = "Could not listen on any of \(ports). Another program may be using them."
        logger.error("Browser bridge could not start: no candidate port was free")
    }

    func stop() {
        startTask?.cancel()
        startTask = nil
        listener?.cancel()
        listener = nil
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
        activePort = nil
        logger.info("Browser bridge stopped")
    }

    /// Brings the server in line with the setting. Called at launch and whenever it is toggled.
    func applySetting() {
        if BrowserBridgeSettings.isEnabled {
            start()
        } else {
            stop()
        }
    }

    // MARK: - Listening

    /// Binds one port, returning only once the listener is actually ready — or throwing if it
    /// never gets there.
    private func listen(on port: UInt16) async throws {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else {
            throw BridgeError.invalidPort(port)
        }

        let parameters = NWParameters.tcp
        // Loopback only, by interface rather than by endpoint. `requiredLocalEndpoint` describes
        // the *local* end of an outbound connection; on a listener it does not restrict what is
        // accepted, and setting it here stopped the listener binding at all. Without a restriction
        // of some kind the socket would answer on the local network, which turns an opt-in
        // convenience into an open model server on whatever Wi-Fi the user is on.
        parameters.requiredInterfaceType = .loopback
        parameters.allowLocalEndpointReuse = true

        let listener = try NWListener(using: parameters, on: nwPort)
        listener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor [weak self] in
                self?.accept(connection, boundPort: port)
            }
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Resumed exactly once: `NWListener` can report further state changes after it is
            // ready, and resuming a continuation twice is a crash.
            let hasResumed = OSAllocatedUnfairLock(initialState: false)

            listener.stateUpdateHandler = { [weak self] state in
                let shouldResume = hasResumed.withLock { resumed -> Bool in
                    guard !resumed, state.isSettled else { return false }
                    resumed = true
                    return true
                }

                switch state {
                case .ready:
                    if shouldResume {
                        continuation.resume()
                    }
                case let .failed(error):
                    if shouldResume {
                        continuation.resume(throwing: error)
                    } else {
                        // Failed after it had been serving. Nothing to hand back, so tear down.
                        Task { @MainActor [weak self] in
                            self?.logger.error(
                                "Browser bridge listener failed: \(error.localizedDescription, privacy: .public)"
                            )
                            self?.stop()
                        }
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
            }
        } onCancel: {
            // Without this a cancelled start sits here until the bind settles, and the socket
            // opens after the user has already switched the bridge off.
            listener.cancel()
        }

        self.listener = listener
    }

    private func accept(_ nwConnection: NWConnection, boundPort: UInt16) {
        // Checked even though `requiredInterfaceType` already filters non-loopback traffic — the
        // socket binds to the wildcard address, so "only this Mac can reach it" rests entirely on
        // that filter. The whole privacy claim rests on it too, which is more weight than one
        // parameter should carry alone.
        guard Self.isLoopback(nwConnection.endpoint) else {
            logger.error("Browser bridge refused a connection from off this Mac")
            nwConnection.cancel()
            return
        }

        guard connections.count < AppConstants.BrowserBridge.maxConcurrentConnections else {
            logger.warning("Browser bridge refused a connection: too many already open")
            nwConnection.cancel()
            return
        }

        let connection = Connection(
            nwConnection: nwConnection, queue: queue, boundPort: boundPort
        ) { [weak self] identifier in
            Task { @MainActor [weak self] in
                self?.connections.removeValue(forKey: identifier)
            }
        }
        connections[ObjectIdentifier(connection)] = connection
        connection.start()
    }

    /// Whether a peer is on this machine.
    static func isLoopback(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        switch host {
        case let .ipv4(address): return address.isLoopback
        case let .ipv6(address): return address.isLoopback || address.asIPv4?.isLoopback == true
        default: return false
        }
    }

    enum BridgeError: Error, LocalizedError {
        case invalidPort(UInt16)

        var errorDescription: String? {
            switch self {
            case let .invalidPort(port): "Port \(port) is not usable."
            }
        }
    }
}

// MARK: - Connection

extension BrowserBridgeServer {
    /// One client connection, reading requests and writing answers until it closes.
    ///
    /// `@unchecked Sendable` because every mutable field is touched only from `queue`, the serial
    /// dispatch queue this connection's `NWConnection` callbacks are delivered on. The one place
    /// that leaves the queue is the handler `Task`, which reads the parsed request — a value type
    /// it owns — and comes back through `send`, which hops onto `queue` before touching anything.
    final class Connection: @unchecked Sendable {
        private let nwConnection: NWConnection
        private let queue: DispatchQueue
        /// The port this connection arrived on, so `Host` can be checked against it without a
        /// hop to the main actor for `activePort`.
        private let boundPort: UInt16
        private let onClose: @Sendable (ObjectIdentifier) -> Void
        private var buffer = Data()
        /// Lock-protected because the streaming handler asks whether the client is still there
        /// from the main actor, while everything else touches it on `queue`.
        private let closed = OSAllocatedUnfairLock(initialState: false)

        /// The tail of this connection's response chain, so pipelined requests are answered in
        /// the order they arrived. Locked because `drainBuffer` runs on `queue` while the task
        /// it chains resumes on whatever executor finished the previous one.
        private let pending = OSAllocatedUnfairLock<Task<Void, Never>?>(initialState: nil)

        private var isClosed: Bool {
            get { closed.withLock { $0 } }
            set { closed.withLock { $0 = newValue } }
        }

        /// Whether the client is still on the other end.
        ///
        /// A stream asks this between tokens. Without it, a browser that closed the tab — or a
        /// user who pressed stop — left the Mac generating an answer nobody would ever read,
        /// holding the inference gate against whatever asked next.
        var isLive: Bool {
            !isClosed
        }

        init(
            nwConnection: NWConnection,
            queue: DispatchQueue,
            boundPort: UInt16,
            onClose: @escaping @Sendable (ObjectIdentifier) -> Void
        ) {
            self.nwConnection = nwConnection
            self.queue = queue
            self.boundPort = boundPort
            self.onClose = onClose
        }

        func start() {
            nwConnection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .cancelled, .failed:
                    self?.close()
                default:
                    break
                }
            }
            nwConnection.start(queue: queue)
            receive()
        }

        func close() {
            queue.async { [weak self] in
                guard let self, !isClosed else { return }
                isClosed = true
                // Anything still queued is answering a client that has gone. Cancelling
                // propagates into `complete()`, which unwinds and releases the inference gate
                // rather than generating to the end for nobody.
                pending.withLock { chain in
                    chain?.cancel()
                    chain = nil
                }
                nwConnection.cancel()
                onClose(ObjectIdentifier(self))
            }
        }

        private func receive() {
            nwConnection.receive(
                minimumIncompleteLength: 1, maximumLength: Self.readChunkBytes
            ) { [weak self] data, _, done, error in
                self?.handleRead(data: data, isComplete: done, error: error)
            }
        }

        private func handleRead(data: Data?, isComplete: Bool, error: NWError?) {
            if let error {
                Logger(subsystem: AppConstants.bundleID, category: "BrowserBridge")
                    .debug("Browser bridge read ended: \(error.localizedDescription, privacy: .public)")
                close()
                return
            }
            if let data, !data.isEmpty {
                buffer.append(data)
                drainBuffer()
            }
            if isComplete {
                close()
            } else if !isClosed {
                receive()
            }
        }

        /// How much is taken off the socket per read. One page of chat context arrives in a few
        /// of these; smaller would only mean more wake-ups.
        private static let readChunkBytes = 64 * 1024

        /// Takes as many complete requests out of the buffer as it holds.
        private func drainBuffer() {
            while !isClosed {
                do {
                    let (request, consumed) = try HTTPMessage.parseRequest(from: buffer)
                    buffer.removeFirst(consumed)
                    dispatch(request)
                } catch HTTPMessage.ParseError.incomplete {
                    return
                } catch HTTPMessage.ParseError.unsupportedFraming {
                    send(
                        .error("This bridge does not accept chunked requests.", status: 501),
                        origin: nil, keepAlive: false, thenClose: true
                    )
                    return
                } catch {
                    send(.error("Bad request.", status: 400), origin: nil, keepAlive: false)
                    close()
                    return
                }
            }
        }

        private func dispatch(_ request: HTTPMessage.Request) {
            let origin = request.header("Origin")
            let decision = BrowserBridgeRoute.decide(
                method: request.method,
                path: request.path,
                origin: origin,
                host: request.header("Host"),
                port: boundPort
            )
            let allowedOrigin = BrowserBridgeRoute.isAllowed(origin: origin) ? origin : nil

            // Chained rather than spawned loose. `drainBuffer` can take several pipelined
            // requests out of the buffer in one pass, and handing each to its own Task ran them
            // concurrently — so responses were written in completion order and a client would
            // pair response #2 with request #1. Worse with SSE, where a second response would
            // land in the middle of an in-flight event stream. HTTP/1.1 requires responses in
            // request order on a persistent connection.
            pending.withLock { chain in
                let previous = chain
                chain = Task { [weak self] in
                    await previous?.value
                    guard let self, !isClosed else { return }
                    await BrowserBridgeServer.shared.handle(
                        decision: decision, request: request, origin: allowedOrigin, on: self
                    )
                }
            }
        }

        /// Writes a complete response.
        ///
        /// `thenClose` closes only once the bytes have actually been handed to the network.
        /// Calling `close()` straight after a `send` cancelled the connection while the write was
        /// still in flight, and the client got an empty reply instead of the status — which is how
        /// a deliberate `403` arrived looking like a crash.
        func send(
            _ response: HTTPMessage.Response,
            origin: String?,
            keepAlive: Bool,
            streaming: Bool = false,
            thenClose: Bool = false
        ) {
            let data = HTTPMessage.serialise(
                response, allowedOrigin: origin, keepAlive: keepAlive, streaming: streaming
            )
            write(data, thenClose: thenClose)
        }

        /// Writes raw bytes — used for the frames of an event stream after its head has gone out.
        func write(_ data: Data, thenClose: Bool = false) {
            queue.async { [weak self] in
                guard let self, !isClosed else { return }
                nwConnection.send(content: data, completion: .contentProcessed { [weak self] error in
                    if let error {
                        Logger(subsystem: AppConstants.bundleID, category: "BrowserBridge")
                            .debug("Browser bridge write failed: \(error.localizedDescription, privacy: .public)")
                    }
                    if thenClose {
                        self?.close()
                    }
                })
            }
        }
    }
}

private extension NWListener.State {
    /// Whether this state is a final answer to "did the bind work?".
    var isSettled: Bool {
        switch self {
        case .ready, .failed: true
        default: false
        }
    }
}
