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

    @Test("End to end: same-project Sessions carry distinct titles, and a /rename updates one (#32)")
    func sessionTitlesAreDistinctAndReflectRename() async throws {
        let harness = try await ServerHarness()

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-titles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // One transcript file per Session (the file name is the session id).
        // The auto title is an `ai-title`; a manual /rename is a `custom-title`.
        func writeTranscript(_ id: String, auto: String, custom: String? = nil) throws -> URL {
            let url = dir.appendingPathComponent("\(id).jsonl")
            var lines = [#"{"type":"ai-title","aiTitle":"\#(auto)","sessionId":"\#(id)"}"#]
            if let custom {
                lines.append(#"{"type":"custom-title","customTitle":"\#(custom)","sessionId":"\#(id)"}"#)
            }
            try Data(lines.joined(separator: "\n").utf8).write(to: url)
            return url
        }
        func hook(_ id: String, _ eventName: String, transcript: URL, extra: String = "") -> String {
            """
            {
              "session_id": "\(id)",
              "transcript_path": "\(transcript.path)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "\(eventName)"\(extra)
            }
            """
        }

        // Two Sessions in the SAME project (same cwd) but distinct titles.
        let t1 = try writeTranscript("s1", auto: "Fix the parser crash")
        let t2 = try writeTranscript("s2", auto: "Ship the release")
        _ = try await harness.postHook(hook("s1", "UserPromptSubmit", transcript: t1, extra: #", "prompt": "Go""#), token: harness.token)
        _ = try await harness.postHook(hook("s2", "UserPromptSubmit", transcript: t2, extra: #", "prompt": "Go""#), token: harness.token)

        try await harness.waitUntil { $0.sessions.count == 2 && $0.sessions.allSatisfy { $0.title != nil } }
        let byID = Dictionary(uniqueKeysWithValues: harness.store.sessions.map { ($0.id, $0) })
        #expect(byID["s1"]?.projectName == "island")
        #expect(byID["s2"]?.projectName == "island")
        // Same project, yet the titles distinguish the two Sessions.
        #expect(byID["s1"]?.title == "Fix the parser crash")
        #expect(byID["s2"]?.title == "Ship the release")

        // A /rename writes a custom-title (the auto title stays); the next event
        // of any kind picks it up, and the manual rename wins.
        _ = try writeTranscript("s1", auto: "Fix the parser crash", custom: "Renamed after /rename")
        _ = try await harness.postHook(hook("s1", "PreToolUse", transcript: t1, extra: #", "tool_name": "Bash""#), token: harness.token)

        try await harness.waitUntil { $0.sessions.first { $0.id == "s1" }?.title == "Renamed after /rename" }
        // The other Session's title is untouched.
        #expect(harness.store.sessions.first { $0.id == "s2" }?.title == "Ship the release")
    }

    @Test("A hook fired inside a Sous-agent (agent_id present) creates no Session (#31/#48)")
    func subagentHookWithNoParentCreatesNoSession() async throws {
        let harness = try await ServerHarness()
        // A Sous-agent's own tool hook carries an agent_id: the adapter drops it
        // (the parent's live Sous-agents are read from the Stop's background_tasks
        // instead), so it never creates or touches a Session.
        let fixture = Self.stopFixture.replacingOccurrences(
            of: #""hook_event_name": "Stop""#,
            with: #""hook_event_name": "PreToolUse", "tool_name": "Bash", "agent_id": "sub-1""#
        )

        let (status, _) = try await harness.postHook(fixture, token: harness.token)

        #expect(status == 200)
        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.store.sessions.isEmpty)
    }

    @Test("An idle notification never resurrects an ended Session into '?' (#31)")
    func idleNotificationLeavesEndedSessionTerminated() async throws {
        let harness = try await ServerHarness()

        _ = try await harness.postHook(Self.stopFixture, token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .ended }

        // The ~60 s idle notification fires the Notification hook on the same
        // Session: it must leave the finished turn "terminé", not turn it "?".
        let idle = """
        {
          "session_id": "abc123",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Notification",
          "notification_type": "idle_prompt",
          "message": "Claude is waiting for your input"
        }
        """
        _ = try await harness.postHook(idle, token: harness.token)

        try await Task.sleep(for: .milliseconds(100))
        #expect(harness.store.sessions[0].state == .ended)
    }

    @Test("A Session with a live Sous-agent (background_tasks) is never 'terminée' until zero (#48)")
    func subagentInFlightNeverShowsTerminatedEndToEnd() async throws {
        let harness = try await ServerHarness()
        func hook(_ eventName: String, extra: String = "") -> String {
            """
            {
              "session_id": "sub-parent",
              "transcript_path": "/tmp/sub-parent.jsonl",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "\(eventName)"\(extra)
            }
            """
        }
        // A Stop whose background_tasks still lists a live Sous-agent, then one
        // where it is empty (the ground-truth JSON-array wire format, #48).
        let liveSubagent = #", "last_assistant_message": "Working…", "background_tasks": [{"id": "sub-1", "type": "subagent", "status": "running"}]"#
        let noSubagent = #", "last_assistant_message": "Done exploring.", "background_tasks": []"#

        _ = try await harness.postHook(hook("UserPromptSubmit", extra: #", "prompt": "Explore""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .running }

        // Main Stop fires while a Sous-agent is still running (constat): the gate
        // keeps it running, read straight from background_tasks — race-free.
        _ = try await harness.postHook(hook("Stop", extra: liveSubagent), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.activeSubagentCount == 1 }
        #expect(harness.store.sessions[0].state == .running) // never terminée yet

        // The Sous-agent finished ⇒ a fresh Stop reports an empty list: ended.
        _ = try await harness.postHook(hook("Stop", extra: noSubagent), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .ended }
        #expect(harness.store.sessions[0].activeSubagentCount == 0)
    }

    // MARK: - A turn ending on a question is "attend", not "terminé" (issue #39)

    /// Writes a one-turn transcript whose last assistant message is `lastText`
    /// and returns its URL — the adapter reads the question from the transcript
    /// (ADR-0002), not from the hook's `last_assistant_message` field.
    private func writeTranscript(lastAssistantText: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-q-\(UUID().uuidString).jsonl")
        let encoded = String(data: try JSONEncoder().encode(lastAssistantText), encoding: .utf8)!
        try Data("""
            {"isSidechain":false,"type":"user","message":{"role":"user","content":"Go"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z"}
            {"isSidechain":false,"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"text","text":\(encoded)}]},"uuid":"a-1","timestamp":"2026-07-19T10:00:42.000Z"}
            """.utf8).write(to: url)
        return url
    }

    @Test("End to end: a turn ending on a question publishes a waiting Session, not terminated (#39)")
    func stopEndingOnQuestionPublishesWaitingSession() async throws {
        let harness = try await ServerHarness()
        let transcript = try writeTranscript(
            lastAssistantText: "I can target Postgres or SQLite. Which do you want?")
        defer { try? FileManager.default.removeItem(at: transcript) }

        let fixture = """
        {
          "session_id": "q1",
          "transcript_path": "\(transcript.path)",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Stop"
        }
        """

        _ = try await harness.postHook(fixture, token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .waiting }

        let session = try #require(harness.store.sessions.first)
        #expect(session.state == .waiting)        // orange, "attend" — not green
        #expect(session.needsAcknowledgement)     // the Liseré lights
        // The question is kept so the Peek can show it (« projet · attend : "…?" »).
        #expect(session.lastSummary?.text == "I can target Postgres or SQLite. Which do you want?")
    }

    @Test("End to end: a turn ending on a constat still publishes a terminated Session (#39)")
    func stopEndingOnConstatPublishesTerminatedSession() async throws {
        let harness = try await ServerHarness()
        let transcript = try writeTranscript(lastAssistantText: "Done — the release is tagged.")
        defer { try? FileManager.default.removeItem(at: transcript) }

        let fixture = """
        {
          "session_id": "c1",
          "transcript_path": "\(transcript.path)",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Stop"
        }
        """

        _ = try await harness.postHook(fixture, token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .ended }
        #expect(harness.store.sessions[0].state == .ended)
    }

    @Test("End to end: a final question with a live Sous-agent waits IMMEDIATELY (Q5, #48)")
    func questionWithLiveSubagentWaitsImmediatelyEndToEnd() async throws {
        let harness = try await ServerHarness()
        let transcript = try writeTranscript(lastAssistantText: "Ready to merge — proceed?")
        defer { try? FileManager.default.removeItem(at: transcript) }
        func hook(_ eventName: String, transcriptPath: String = "/tmp/qsub.jsonl", extra: String = "") -> String {
            """
            {
              "session_id": "qsub",
              "transcript_path": "\(transcriptPath)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "\(eventName)"\(extra)
            }
            """
        }

        _ = try await harness.postHook(hook("UserPromptSubmit", extra: #", "prompt": "Prepare the merge""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .running }

        // The main turn ends on a question WHILE a Sous-agent is still live in
        // background_tasks: the question wins immediately (orange), the gate only
        // ever holds back the green of a constat (Q5 corrects the old deferral).
        let liveSubagent = #", "background_tasks": [{"id": "sub-1", "type": "subagent", "status": "running"}]"#
        _ = try await harness.postHook(hook("Stop", transcriptPath: transcript.path, extra: liveSubagent), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .waiting }
        #expect(harness.store.sessions[0].needsAcknowledgement)
    }

    @Test("End to end REAL REPRO: a lagging transcript still publishes waiting via last_assistant_message (#39)")
    func laggingTranscriptStillPublishesWaitingViaPayload() async throws {
        let harness = try await ServerHarness()
        // The transcript LAGS at Stop (Claude Code docs): its last assistant
        // text is still the OLD constat, while the payload's authoritative
        // last_assistant_message is the fresh question. The Session must still
        // land orange "attend" — the real FP that failed before the fix.
        let stale = try writeTranscript(lastAssistantText: "Working on it.")
        defer { try? FileManager.default.removeItem(at: stale) }

        let fixture = """
        {
          "session_id": "lag1",
          "transcript_path": "\(stale.path)",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Stop",
          "last_assistant_message": "Postgres or SQLite — which do you want?"
        }
        """

        _ = try await harness.postHook(fixture, token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .waiting }
        let session = try #require(harness.store.sessions.first)
        #expect(session.state == .waiting)
        #expect(session.needsAcknowledgement)
        #expect(session.lastSummary?.text == "Postgres or SQLite — which do you want?")
    }

    // MARK: - Case 4 replayed from the REAL capture: an Agent background subagent (#39)

    @Test("REAL CAPTURE: an Agent-subagent turn ending on a question publishes waiting, the subagent's own hooks ignored (#39 case 4)")
    func agentSubagentTurnEndingOnQuestionWaits() async throws {
        let harness = try await ServerHarness()
        let p = "parent-ed31"
        func hook(_ event: String, extra: String = "") -> String {
            """
            {
              "session_id": "\(p)",
              "transcript_path": "/tmp/\(p).jsonl",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "\(event)"\(extra)
            }
            """
        }

        // The exact captured case-4 sequence (session ed31cce6, log lines
        // 141-155): a prompt, the `Agent` background-subagent spawn tool (a
        // plain main-session tool — NOT the never-installed SubagentStart, NOT
        // the wrongly-guessed Task gate), the subagent's own tool hook carrying
        // an agent_id (dropped), then the main Stop carrying the question.
        _ = try await harness.postHook(hook("UserPromptSubmit", extra: #", "prompt": "lance un sous-agent et termine par une question""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .running }

        _ = try await harness.postHook(hook("PreToolUse", extra: #", "tool_name": "Agent", "tool_input": {"description": "sous-agent bidon"}"#), token: harness.token)
        _ = try await harness.postHook(hook("PostToolUse", extra: #", "tool_name": "Agent""#), token: harness.token)

        // The background subagent's own tool call (agent_id present) must be
        // dropped — never touching the parent (log lines 175/179/193/194).
        _ = try await harness.postHook(hook("PreToolUse", extra: #", "tool_name": "Bash", "agent_id": "aagent-bidon""#), token: harness.token)

        // The main agent asks its question and stops. The transcript may lag, so
        // the question rides on last_assistant_message (the #39 real fix): the
        // parent resolves ORANGE on its OWN Stop, regardless of the subagent.
        _ = try await harness.postHook(hook("Stop", extra: #", "last_assistant_message": "tu veux que je l'arrête tout de suite ?""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .waiting }

        #expect(harness.store.sessions.count == 1)  // the agent_id hook created no second Session
        let session = try #require(harness.store.sessions.first)
        #expect(session.state == .waiting)
        #expect(session.needsAcknowledgement)
        #expect(session.lastSummary?.text == "tu veux que je l'arrête tout de suite ?")
    }

    @Test("REAL CAPTURE: an Agent-subagent turn ending on a constat publishes ended (#39 case 4 contrast)")
    func agentSubagentTurnEndingOnConstatEnds() async throws {
        let harness = try await ServerHarness()
        let p = "parent-ed32"
        func hook(_ event: String, extra: String = "") -> String {
            """
            {
              "session_id": "\(p)",
              "transcript_path": "/tmp/\(p).jsonl",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "\(event)"\(extra)
            }
            """
        }

        _ = try await harness.postHook(hook("UserPromptSubmit", extra: #", "prompt": "lance un sous-agent et ne termine PAS par une question""#), token: harness.token)
        try await harness.waitUntil { $0.sessions.first?.state == .running }
        _ = try await harness.postHook(hook("PreToolUse", extra: #", "tool_name": "Agent""#), token: harness.token)
        _ = try await harness.postHook(hook("PostToolUse", extra: #", "tool_name": "Agent""#), token: harness.token)
        _ = try await harness.postHook(hook("PreToolUse", extra: #", "tool_name": "Bash", "agent_id": "aagent-bidon""#), token: harness.token)
        _ = try await harness.postHook(hook("Stop", extra: #", "last_assistant_message": "Dis-moi quand tu veux que je l'arrête.""#), token: harness.token)

        try await harness.waitUntil { $0.sessions.first?.state == .ended }
        #expect(harness.store.sessions.count == 1)
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
