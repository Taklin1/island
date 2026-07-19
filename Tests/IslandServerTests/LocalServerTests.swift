import Foundation
import Testing
import ClaudeCodeAdapter
import IslandServer
import IslandStore

/// Integration tests of the local server seam (PRD #3, Testing Decisions):
/// POST real hook fixtures over HTTP and assert the published Sessions —
/// never the internals.
@MainActor
struct LocalServerTests {
    static let stopFixture = """
    {
      "session_id": "abc123",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "permission_mode": "default",
      "hook_event_name": "Stop",
      "last_assistant_message": "Done."
    }
    """

    @Test("POSTing a Stop fixture with a valid token publishes a terminated Session")
    func stopFixturePublishesTerminatedSession() async throws {
        let harness = try await ServerHarness()

        let (status, _) = try await harness.postHook(Self.stopFixture, token: harness.token)

        #expect(status == 200)
        try await harness.waitUntil { !$0.sessions.isEmpty }
        #expect(harness.store.sessions.count == 1)
        #expect(harness.store.sessions[0].id == "abc123")
        #expect(harness.store.sessions[0].state == .ended)
        #expect(harness.store.sessions[0].projectName == "island")
    }

    @Test("The token is also accepted in the X-Island-Token header")
    func tokenAcceptedInHeader() async throws {
        let harness = try await ServerHarness()

        let (status, _) = try await harness.postHook(
            Self.stopFixture,
            token: harness.token,
            tokenInHeader: true
        )

        #expect(status == 200)
        try await harness.waitUntil { !$0.sessions.isEmpty }
        #expect(harness.store.sessions[0].state == .ended)
    }

    @Test("A request without a valid token gets 401 and publishes nothing")
    func invalidTokenIsRejected() async throws {
        let harness = try await ServerHarness()

        let (missing, _) = try await harness.postHook(Self.stopFixture, token: nil)
        let (wrong, _) = try await harness.postHook(Self.stopFixture, token: "wrong-token")

        #expect(missing == 401)
        #expect(wrong == 401)
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.store.sessions.isEmpty)
    }

    @Test("A full hook sequence drives the Session lifecycle end to end")
    func fullHookSequenceDrivesSessionLifecycle() async throws {
        let harness = try await ServerHarness()
        func fixture(_ eventName: String, extra: String = "") -> String {
            """
            {
              "session_id": "seq1",
              "transcript_path": "/tmp/seq1.jsonl",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "\(eventName)"\(extra)
            }
            """
        }

        _ = try await harness.postHook(fixture("SessionStart", extra: #", "source": "startup""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .idle }

        _ = try await harness.postHook(fixture("UserPromptSubmit", extra: #", "prompt": "Fix the login bug""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .running }
        #expect(harness.store.sessions[0].lastPrompt == "Fix the login bug")

        _ = try await harness.postHook(fixture("PreToolUse", extra: #", "tool_name": "Bash", "tool_input": {"command": "ls"}"#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.currentTool == "Bash" }

        _ = try await harness.postHook(fixture("PostToolUse", extra: #", "tool_name": "Bash", "tool_input": {"command": "ls"}, "tool_response": "done""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.currentTool == nil }

        _ = try await harness.postHook(fixture("Stop", extra: #", "last_assistant_message": "Done.""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .ended }
        #expect(harness.store.sessions.count == 1)

        _ = try await harness.postHook(fixture("SessionEnd", extra: #", "reason": "prompt_input_exit""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.isEmpty }
    }

    @Test("Two simultaneous sessions stay visible and distinct")
    func twoSimultaneousSessionsAreDistinct() async throws {
        let harness = try await ServerHarness()
        func fixture(_ id: String, _ eventName: String, cwd: String, extra: String = "") -> String {
            """
            {
              "session_id": "\(id)",
              "transcript_path": "/tmp/\(id).jsonl",
              "cwd": "\(cwd)",
              "hook_event_name": "\(eventName)"\(extra)
            }
            """
        }

        _ = try await harness.postHook(fixture("s1", "SessionStart", cwd: "/tmp/projet-a"), token: harness.token)
        _ = try await harness.postHook(fixture("s2", "SessionStart", cwd: "/tmp/projet-b"), token: harness.token)
        _ = try await harness.postHook(fixture("s2", "UserPromptSubmit", cwd: "/tmp/projet-b", extra: #", "prompt": "Go""#), token: harness.token)

        try await harness.waitUntil { store in
            store.sessions.count == 2 && store.sessions.contains { $0.state == .running }
        }
        let byID = Dictionary(uniqueKeysWithValues: harness.store.sessions.map { ($0.id, $0) })
        #expect(byID["s1"]?.projectName == "projet-a")
        #expect(byID["s1"]?.state == .idle)
        #expect(byID["s2"]?.projectName == "projet-b")
        #expect(byID["s2"]?.state == .running)
    }

    @Test("A SubagentStop fixture is acknowledged but publishes nothing")
    func subagentStopIsIgnored() async throws {
        let harness = try await ServerHarness()
        let fixture = Self.stopFixture.replacingOccurrences(
            of: #""hook_event_name": "Stop""#,
            with: #""hook_event_name": "SubagentStop""#
        )

        let (status, _) = try await harness.postHook(fixture, token: harness.token)

        #expect(status == 200)
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.store.sessions.isEmpty)
    }
}

/// Boots a LocalServer on an ephemeral port, wired exactly like the app:
/// Claude Code adapter → session store on the main actor.
@MainActor
final class ServerHarness {
    let store = SessionStore()
    let token = "test-token-\(UUID().uuidString)"
    let server: LocalServer
    let port: UInt16

    init() async throws {
        let store = store
        server = LocalServer(
            port: 0,
            token: token,
            translate: ClaudeCodeAdapter.event(fromHookPayload:),
            publish: { event in
                Task { @MainActor in store.apply(event) }
            }
        )
        port = try await server.start()
    }

    deinit {
        server.stop()
    }

    func postHook(
        _ body: String,
        token: String?,
        tokenInHeader: Bool = false
    ) async throws -> (status: Int, body: Data) {
        var components = URLComponents(string: "http://127.0.0.1:\(port)/hooks/claude-code")!
        if let token, !tokenInHeader {
            components.queryItems = [URLQueryItem(name: "token", value: token)]
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token, tokenInHeader {
            request.setValue(token, forHTTPHeaderField: "X-Island-Token")
        }
        request.timeoutInterval = 5

        let (data, response) = try await URLSession.shared.data(for: request)
        return ((response as! HTTPURLResponse).statusCode, data)
    }

    /// Polls the store (the server answers before the store publishes).
    func waitUntil(
        timeout: TimeInterval = 2,
        _ condition: @MainActor (SessionStore) -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(store) {
            guard Date() < deadline else {
                throw HarnessError.timedOutWaitingForStore
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    enum HarnessError: Error {
        case timedOutWaitingForStore
    }
}
