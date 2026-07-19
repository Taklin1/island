import Foundation
import Testing
import ClaudeCodeAdapter
import IslandServer
import IslandStore

/// Statusline tee seam (issue #9): POST the JSON Claude Code pipes into the
/// statusline command and assert the published Quotas — never the internals.
@MainActor
struct StatuslineEndpointTests {
    static let statuslineFixture = """
    {
      "session_id": "quota-e2e-1",
      "cwd": "/Users/loic/Documents/island",
      "model": { "id": "claude-opus-4-6", "display_name": "Opus" },
      "context_window": { "used_percentage": 17.3 },
      "rate_limits": {
        "five_hour": { "used_percentage": 23.5, "resets_at": 1738425600 },
        "seven_day": { "used_percentage": 41.2, "resets_at": 1738857600 }
      }
    }
    """

    @Test("POSTing a statusline fixture with a valid token publishes the Quotas")
    func statuslineFixturePublishesQuotas() async throws {
        let harness = try await StatuslineHarness()

        let (status, _) = try await harness.post(
            path: "/statusline/claude-code", body: Self.statuslineFixture, token: harness.token)

        #expect(status == 200)
        try await harness.waitUntil { $0.quotas != nil }
        #expect(harness.quotaStore.quotas?.fiveHour?.usedPercentage == 23.5)
        #expect(harness.quotaStore.quotas?.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_738_425_600))
        #expect(harness.quotaStore.quotas?.sevenDay?.usedPercentage == 41.2)
        #expect(harness.quotaStore.contextBySession["quota-e2e-1"] == 17.3)
    }

    @Test("A statusline POST without a valid token gets 401 and publishes nothing")
    func statuslineInvalidTokenIsRejected() async throws {
        let harness = try await StatuslineHarness()

        let (status, _) = try await harness.post(
            path: "/statusline/claude-code", body: Self.statuslineFixture, token: "wrong")

        #expect(status == 401)
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.quotaStore.quotas == nil)
    }

    @Test("An unreadable statusline payload is acknowledged and ignored")
    func unreadableStatuslinePayloadIsIgnored() async throws {
        let harness = try await StatuslineHarness()

        let (status, _) = try await harness.post(
            path: "/statusline/claude-code", body: "not json at all", token: harness.token)

        #expect(status == 200)
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.quotaStore.quotas == nil)
        #expect(harness.quotaStore.contextBySession.isEmpty)
    }
}

/// Boots a LocalServer on an ephemeral port with the statusline route wired
/// exactly like the app: statusline JSON → QuotaUpdate → QuotaStore.
@MainActor
final class StatuslineHarness {
    let quotaStore = QuotaStore()
    let token = "test-token-\(UUID().uuidString)"
    let server: LocalServer
    let port: UInt16

    init() async throws {
        let quotaStore = quotaStore
        server = LocalServer(
            port: 0,
            token: token,
            translate: ClaudeCodeAdapter.event(fromHookPayload:),
            publish: { _ in },
            translateStatusline: QuotaUpdate.init(statuslineJSON:),
            publishQuota: { update in
                Task { @MainActor in quotaStore.apply(update) }
            }
        )
        port = try await server.start()
    }

    deinit {
        server.stop()
    }

    func post(path: String, body: String, token: String?) async throws -> (status: Int, body: Data) {
        var components = URLComponents(string: "http://127.0.0.1:\(port)\(path)")!
        if let token {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, data)
    }

    /// Polls the quota store (the server answers before the store publishes).
    func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor (QuotaStore) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(quotaStore) {
            guard Date() < deadline else {
                throw ServerHarness.HarnessError.timedOutWaitingForStore
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}
