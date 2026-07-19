import Foundation
import IslandStore
import Network

/// Local HTTP entry point for events (ADR-0001).
///
/// Listens on 127.0.0.1 only, authenticates every request with the token
/// (`?token=` query parameter or `X-Island-Token` header) and answers
/// immediately — publishing to the store happens asynchronously so a hook
/// never waits on the UI. The server itself never sees the hook format: the
/// injected `translate` closure (an adapter) turns raw payloads into generic
/// events (ADR-0004).
public final class LocalServer: @unchecked Sendable {
    /// Turns a raw adapter-specific payload into a generic event
    /// (`nil` = ignored payload, e.g. SubagentStop).
    public typealias Translator = @Sendable (Data) -> AgentEvent?
    /// Hands a translated event over to the rest of the app. Must not block.
    public typealias Publisher = @Sendable (AgentEvent) -> Void

    /// Fixed production port. Tests pass 0 for an ephemeral port.
    public static let defaultPort: UInt16 = 41414

    private static let maxRequestBytes = 1 << 20

    private let queue = DispatchQueue(label: "island.local-server")
    private let requestedPort: UInt16
    private let token: String
    private let translate: Translator
    private let publish: Publisher
    private var listener: NWListener?

    public init(
        port: UInt16 = LocalServer.defaultPort,
        token: String,
        translate: @escaping Translator,
        publish: @escaping Publisher
    ) {
        self.requestedPort = port
        self.token = token
        self.translate = translate
        self.publish = publish
    }

    /// Starts listening; returns the resolved port once ready.
    public func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Loopback only: the server must never be reachable from the network.
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: requestedPort)!
        )

        let listener = try NWListener(using: parameters)
        self.listener = listener

        listener.newConnectionHandler = { [weak self] connection in
            guard let self else {
                connection.cancel()
                return
            }
            connection.start(queue: self.queue)
            self.receive(on: connection, buffered: Data())
        }

        return try await withCheckedThrowingContinuation { continuation in
            let resumeOnce = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resumeOnce.claim() {
                        continuation.resume(returning: listener.port?.rawValue ?? 0)
                    }
                case let .failed(error):
                    if resumeOnce.claim() {
                        continuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func stop() {
        // Break the listener → stateUpdateHandler → listener retain cycle.
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
    }

    // MARK: - Request handling

    private func receive(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }

            var buffer = buffered
            if let data {
                buffer.append(data)
            }

            if let request = HTTPRequest.parse(buffer) {
                self.respond(to: request, on: connection)
            } else if isComplete || error != nil || buffer.count > Self.maxRequestBytes {
                connection.cancel()
            } else {
                self.receive(on: connection, buffered: buffer)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        let status: (code: Int, reason: String)
        let body: String

        if !isAuthorized(request) {
            (status, body) = ((401, "Unauthorized"), #"{"error":"invalid token"}"#)
        } else if request.method == "POST", request.path == "/hooks/claude-code" {
            // Translate first, answer immediately either way: unhandled hooks
            // (SubagentStop…) and unreadable payloads are silently ignored so
            // Claude Code is never disturbed.
            if let event = translate(request.body) {
                publish(event)
            }
            (status, body) = ((200, "OK"), #"{"ok":true}"#)
        } else {
            (status, body) = ((404, "Not Found"), #"{"error":"not found"}"#)
        }

        var response = "HTTP/1.1 \(status.code) \(status.reason)\r\n"
        response += "Content-Type: application/json\r\n"
        response += "Content-Length: \(body.utf8.count)\r\n"
        response += "Connection: close\r\n\r\n"
        response += body

        connection.send(
            content: Data(response.utf8),
            completion: .contentProcessed { _ in
                connection.cancel()
            }
        )
    }

    private func isAuthorized(_ request: HTTPRequest) -> Bool {
        request.query["token"] == token || request.headers["x-island-token"] == token
    }
}

/// Thread-safe "resume the continuation exactly once" guard.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
