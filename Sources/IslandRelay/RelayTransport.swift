import Foundation

/// How the Relais sends one Instantané (issue #157). Seam in the
/// `UpdateFetcher` shape: a closure-property struct the app wires with
/// ``live``; tests build the live transport with short timeouts against a
/// fake Totem on 127.0.0.1.
public struct RelayTransport: Sendable {
    /// POSTs `body` to the target and returns the HTTP status code. Throws the
    /// untouched transport error (refused, timeout, Local Network denied…) so
    /// the caller can trace it in full. Must honor task cancellation.
    public var post: @Sendable (_ body: Data, _ target: RelayTarget) async throws -> Int

    public init(post: @escaping @Sendable (_ body: Data, _ target: RelayTarget) async throws -> Int) {
        self.post = post
    }

    /// Production transport: ~2 s per request, ~3 s overall.
    public static let live = RelayTransport.live()

    /// A dedicated ephemeral URLSession — never `URLSession.shared`. One
    /// connection per host, no cache, `Connection: close`: the ESP32 server
    /// closes after each answer, and a reused keep-alive socket would fail
    /// with -1005 (network connection lost).
    public static func live(
        requestTimeout: TimeInterval = 2,
        resourceTimeout: TimeInterval = 3
    ) -> RelayTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = requestTimeout
        configuration.timeoutIntervalForResource = resourceTimeout
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.httpShouldUsePipelining = false
        configuration.waitsForConnectivity = false
        let session = URLSession(configuration: configuration)
        return RelayTransport { body, target in
            var request = URLRequest(url: target.endpoint)
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(target.token, forHTTPHeaderField: "X-Island-Token")
            request.setValue("close", forHTTPHeaderField: "Connection")
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode ?? 0
        }
    }
}
