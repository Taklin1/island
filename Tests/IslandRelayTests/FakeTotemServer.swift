import Foundation
@testable import IslandServer
import Network

/// A fake Totem for the Relais tests (issue #157): an `NWListener` on
/// 127.0.0.1, ephemeral port, that records every request (method, route,
/// headers, body) — modeled on `LocalServer`. Like the ESP32 firmware it
/// answers then closes the connection; `.mute` accepts and never answers
/// (the timeout case). Never a real LAN address in tests.
final class FakeTotemServer: @unchecked Sendable {
    /// One recorded request (headers keyed lowercased).
    struct Received: Sendable {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    enum Behavior {
        case respond(status: Int)
        case mute
    }

    let port: UInt16
    var endpoint: URL { URL(string: "http://127.0.0.1:\(port)/snapshot")! }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "island.fake-totem")
    private let lock = NSLock()
    private var recorded: [Received] = []
    /// Mute connections are retained here so they stay open, unanswered.
    private var held: [NWConnection] = []

    init(behavior: Behavior = .respond(status: 200)) async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        let queue = queue
        port = try await withCheckedThrowingContinuation { continuation in
            let once = OnceFlag()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if once.claim() { continuation.resume(returning: listener.port?.rawValue ?? 0) }
                case let .failed(error):
                    if once.claim() { continuation.resume(throwing: error) }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { _ in }
            listener.start(queue: queue)
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return connection.cancel() }
            connection.start(queue: self.queue)
            self.receive(on: connection, buffered: Data(), behavior: behavior)
        }
    }

    deinit { stop() }

    func stop() {
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        lock.withLock {
            held.forEach { $0.cancel() }
            held.removeAll()
        }
    }

    var requests: [Received] { lock.withLock { recorded } }

    /// Every received body decoded as a JSON object.
    var snapshots: [[String: Any]] {
        requests.map { (try? JSONSerialization.jsonObject(with: $0.body)) as? [String: Any] ?? [:] }
    }

    /// Polls until at least `count` requests arrived.
    @discardableResult
    func waitForRequests(count: Int, timeout: TimeInterval = 3) async throws -> [Received] {
        let deadline = Date().addingTimeInterval(timeout)
        while requests.count < count {
            guard Date() < deadline else { throw FakeTotemError.timedOut(received: requests.count) }
            try await Task.sleep(for: .milliseconds(10))
        }
        return requests
    }

    /// A loopback port nobody listens on: connecting is refused at once.
    static func closedPort() async throws -> UInt16 {
        let server = try await FakeTotemServer()
        let port = server.port
        server.stop()
        try await Task.sleep(for: .milliseconds(50))
        return port
    }

    private func receive(on connection: NWConnection, buffered: Data, behavior: Behavior) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) {
            [weak self] data, _, isComplete, error in
            guard let self else { return connection.cancel() }
            var buffer = buffered
            if let data { buffer.append(data) }
            if let request = HTTPRequest.parse(buffer) {
                let received = Received(
                    method: request.method, path: request.path,
                    headers: request.headers, body: request.body)
                self.lock.withLock { self.recorded.append(received) }
                switch behavior {
                case let .respond(status):
                    let response = "HTTP/1.1 \(status) OK\r\nContent-Type: application/json\r\n"
                        + "Content-Length: 2\r\nConnection: close\r\n\r\n{}"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                case .mute:
                    self.lock.withLock { self.held.append(connection) }
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.receive(on: connection, buffered: buffer, behavior: behavior)
            }
        }
    }
}

enum FakeTotemError: Error {
    case timedOut(received: Int)
}

private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.withLock {
            defer { claimed = true }
            return !claimed
        }
    }
}
