import Foundation
import Testing
@testable import ClaudeCodeAdapter
import IslandStore

/// Fixtures mirror the real Claude Code hook payloads
/// (https://code.claude.com/docs/en/hooks): common fields session_id,
/// transcript_path, cwd, hook_event_name.
enum Fixtures {
    static let stop = Data("""
    {
      "session_id": "abc123",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "permission_mode": "default",
      "hook_event_name": "Stop",
      "last_assistant_message": "Done refactoring."
    }
    """.utf8)

    /// A Stop fired while a background `Agent` Sous-agent is still running.
    /// `background_tasks` is a JSON array (issue #48 ground truth): the live
    /// subagent shows up with `type: "subagent"` and an `id` == its agent_id.
    /// A `session_crons` entry sits in a separate field and is not a subagent.
    static let stopWithLiveSubagent = Data("""
    {
      "session_id": "abc123",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "hook_event_name": "Stop",
      "last_assistant_message": "Je lance le sous-agent et j'attends sa fin.",
      "background_tasks": [
        {
          "agent_type": "general-purpose",
          "description": "Liste et résume les fichiers Swift",
          "id": "a52ecbfbd42e9f2a5",
          "status": "running",
          "type": "subagent"
        }
      ],
      "session_crons": [
        { "id": "cron-1", "schedule": "0 9 * * *" }
      ]
    }
    """.utf8)

    /// The follow-up Stop once the Sous-agent has finished: `background_tasks`
    /// is empty, so the turn can resolve (constat ⇒ green).
    static let stopWithNoLiveSubagent = Data("""
    {
      "session_id": "abc123",
      "cwd": "/Users/loic/Documents/island",
      "hook_event_name": "Stop",
      "last_assistant_message": "Terminé, le sous-agent a fini.",
      "background_tasks": []
    }
    """.utf8)

    static let sessionStart = Data("""
    {
      "session_id": "abc123",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "hook_event_name": "SessionStart",
      "source": "startup",
      "model": "claude-sonnet-5"
    }
    """.utf8)

    static let userPromptSubmit = Data("""
    {
      "session_id": "abc123",
      "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "permission_mode": "default",
      "hook_event_name": "UserPromptSubmit",
      "prompt": "Write a test for the login function"
    }
    """.utf8)

    static let preToolUse = Data("""
    {
      "session_id": "abc123",
      "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "permission_mode": "default",
      "hook_event_name": "PreToolUse",
      "tool_name": "Bash",
      "tool_input": {"command": "swift test"}
    }
    """.utf8)

    static let postToolUse = Data("""
    {
      "session_id": "abc123",
      "prompt_id": "550e8400-e29b-41d4-a716-446655440000",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "permission_mode": "default",
      "hook_event_name": "PostToolUse",
      "tool_name": "Bash",
      "tool_input": {"command": "swift test"},
      "tool_response": "Test run with 7 tests passed"
    }
    """.utf8)

    static let sessionEnd = Data("""
    {
      "session_id": "abc123",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "hook_event_name": "SessionEnd",
      "reason": "prompt_input_exit"
    }
    """.utf8)
}

struct ClaudeCodeAdapterTests {
    @Test("SessionStart hook payload becomes a generic 'session started' event")
    func sessionStartBecomesSessionStarted() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.sessionStart))

        #expect(event.sessionID == "abc123")
        #expect(event.kind == .sessionStarted)
        #expect(event.cwd == "/Users/loic/Documents/island")
        #expect(event.agent == "claude-code")
    }

    @Test("SessionEnd hook payload becomes a generic 'session ended' event")
    func sessionEndBecomesSessionEnded() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.sessionEnd))

        #expect(event.sessionID == "abc123")
        #expect(event.kind == .sessionEnded)
    }

    @Test("UserPromptSubmit hook payload carries the prompt text")
    func userPromptSubmitBecomesPromptSubmitted() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.userPromptSubmit))

        #expect(event.kind == .promptSubmitted(prompt: "Write a test for the login function"))
    }

    @Test("PreToolUse hook payload becomes a 'tool started' event with the tool name")
    func preToolUseBecomesToolStarted() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.preToolUse))

        #expect(event.kind == .toolStarted(tool: "Bash"))
    }

    @Test("PostToolUse hook payload becomes a 'tool finished' event")
    func postToolUseBecomesToolFinished() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.postToolUse))

        #expect(event.kind == .toolFinished(tool: "Bash"))
    }

    @Test("A background subagent's tool hook (agent_id present) is ignored — it never touches the parent (#39 case 4)")
    func subagentAgentIdToolHookIsIgnored() {
        // Ground truth from a real case-4 capture: the background subagent (the
        // `Agent`/Task tool) runs in its own session and every one of its tool
        // hooks carries an agent_id. Those must be dropped so they never drive
        // the parent Session — the parent resolves on its own Stop.
        let payload = Data("""
            {
              "session_id": "parent-abc",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "PreToolUse",
              "tool_name": "Bash",
              "agent_id": "aagent-bidon"
            }
            """.utf8)
        #expect(ClaudeCodeAdapter.event(fromHookPayload: payload) == nil)
    }

    @Test("The Agent subagent-spawn tool is a plain tool on the main session (#39 case 4)")
    func agentSpawnToolIsAPlainMainTool() throws {
        // The real subagent spawner is the `Agent` tool; its PreToolUse fires on
        // the MAIN session with NO agent_id, so it is a normal tool call — never
        // a state-changing subagent event (this reverses the wrong Task gate).
        let payload = Data("""
            {
              "session_id": "parent-abc",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "PreToolUse",
              "tool_name": "Agent",
              "tool_input": {"description": "sub", "prompt": "…", "name": "x"}
            }
            """.utf8)
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: payload))
        #expect(event.kind == .toolStarted(tool: "Agent"))
    }

    @Test("Stop hook payload becomes a generic 'turn ended' event")
    func stopPayloadBecomesEndedEvent() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))

        #expect(event.sessionID == "abc123")
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
        #expect(event.cwd == "/Users/loic/Documents/island")
        #expect(event.agent == "claude-code")
    }

    @Test("Stop reads the transcript at transcript_path and attaches the summary")
    func stopAttachesTranscriptSummary() throws {
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-stop-\(UUID().uuidString).jsonl")
        try Data("""
            {"isSidechain":false,"type":"user","message":{"role":"user","content":"Ship it"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z"}
            {"isSidechain":false,"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"text","text":"Shipped: the release is tagged."}]},"uuid":"a-1","timestamp":"2026-07-19T10:00:42.000Z"}
            """.utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }

        let payload = Data("""
            {
              "session_id": "abc123",
              "transcript_path": "\(transcript.path)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "Stop"
            }
            """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: payload))
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
        #expect(event.summary?.text == "Shipped: the release is tagged.")
        #expect(event.summary?.turnDuration == 42)
    }

    @Test("Stop with an unreadable transcript still emits the event, with the payload's final text")
    func stopWithUnreadableTranscriptStillNotifies() throws {
        // ADR-0002: the notification must always go out. The transcript here is
        // unreadable, but the payload's last_assistant_message ("Done
        // refactoring.") still provides the final text — the race-free source
        // Claude Code recommends over the lagging transcript (#39).
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
        #expect(event.summary?.text == "Done refactoring.")
    }

    // MARK: - A turn ending on a question is "attend" (issue #39 / ADR-0006)

    /// Builds a Stop payload pointing at a one-turn transcript whose last
    /// assistant message is `lastText`, and returns the translated event.
    private func stopEvent(lastAssistantText: String) throws -> AgentEvent {
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-q-\(UUID().uuidString).jsonl")
        // JSON-encode the text so quotes/newlines in the message are safe.
        let encodedText = String(
            data: try JSONEncoder().encode(lastAssistantText), encoding: .utf8)!
        try Data("""
            {"isSidechain":false,"type":"user","message":{"role":"user","content":"Go"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z"}
            {"isSidechain":false,"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"text","text":\(encodedText)}]},"uuid":"a-1","timestamp":"2026-07-19T10:00:42.000Z"}
            """.utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }

        let payload = Data("""
            {
              "session_id": "abc123",
              "transcript_path": "\(transcript.path)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "Stop"
            }
            """.utf8)
        return try #require(ClaudeCodeAdapter.event(fromHookPayload: payload))
    }

    @Test("Stop whose last message ends on a question sets awaitsReply true")
    func stopEndingOnQuestionAwaitsReply() throws {
        let event = try stopEvent(
            lastAssistantText: "I can go with Postgres or SQLite. Which do you want?")
        #expect(event.kind == .turnEnded(awaitsReply: true, liveSubagentCount: 0))
    }

    @Test("Stop whose last message ends on a constat sets awaitsReply false")
    func stopEndingOnConstatDoesNotAwaitReply() throws {
        let event = try stopEvent(lastAssistantText: "Done — the parser crash is fixed.")
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
    }

    @Test("A rhetorical '?' mid-message that ends on a constat does not await a reply")
    func rhetoricalQuestionMidMessageDoesNotAwaitReply() throws {
        // Only the very end matters (ADR-0006): a '?' earlier in the message,
        // followed by a concluding statement, is not a question to the user.
        let event = try stopEvent(
            lastAssistantText: "Is it done? Yes — every test passes and it is shipped.")
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
    }

    @Test("Trailing whitespace/newline after the '?' still counts as a question")
    func trailingWhitespaceAfterQuestionStillAwaitsReply() throws {
        let event = try stopEvent(lastAssistantText: "Shall I proceed?\n\n")
        #expect(event.kind == .turnEnded(awaitsReply: true, liveSubagentCount: 0))
    }

    @Test("REAL REPRO: the transcript lags at Stop; the question is detected from last_assistant_message (#39)")
    func questionDetectedFromPayloadWhenTranscriptLags() throws {
        // Root cause of the real FP failure: Claude Code's hooks docs warn the
        // transcript file "may lag behind the in-memory conversation" at Stop —
        // the just-produced final message may not be flushed yet. Here the
        // transcript's last assistant text is still an OLD constat (the message
        // BEFORE the question), while the payload's last_assistant_message is
        // the fresh question. The old code (transcript-only) read the stale
        // constat → awaitsReply false → green. The fix reads the authoritative
        // payload field → true → orange.
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-lag-\(UUID().uuidString).jsonl")
        try Data("""
            {"isSidechain":false,"type":"user","message":{"role":"user","content":"Add persistence"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z"}
            {"isSidechain":false,"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"text","text":"Working on it."}]},"uuid":"a-1","timestamp":"2026-07-19T10:00:10.000Z"}
            """.utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }

        let payload = Data("""
            {
              "session_id": "abc123",
              "transcript_path": "\(transcript.path)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "Stop",
              "last_assistant_message": "I can target Postgres or SQLite. Which do you want?"
            }
            """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: payload))
        #expect(event.kind == .turnEnded(awaitsReply: true, liveSubagentCount: 0))
        // And the authoritative final text wins over the stale transcript, so
        // the Peek shows the real question (« projet · attend : "…?" »).
        #expect(event.summary?.text == "I can target Postgres or SQLite. Which do you want?")
    }

    @Test("last_assistant_message wins over the transcript text (authoritative final text, #39)")
    func lastAssistantMessagePreferredOverTranscriptText() throws {
        // Even when the transcript IS readable, the payload's last_assistant_message
        // is the authoritative final text (Claude Code docs). A stale transcript
        // constat must not override a fresh payload question, nor vice-versa.
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-pref-\(UUID().uuidString).jsonl")
        try Data("""
            {"isSidechain":false,"type":"user","message":{"role":"user","content":"Go"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z"}
            {"isSidechain":false,"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"tool_use","name":"TodoWrite","input":{"todos":[{"content":"x","status":"completed"}]}},{"type":"text","text":"An earlier line, not the end."}]},"uuid":"a-1","timestamp":"2026-07-19T10:00:20.000Z"}
            """.utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }

        let payload = Data("""
            {
              "session_id": "abc123",
              "transcript_path": "\(transcript.path)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "Stop",
              "last_assistant_message": "Everything is wired. Ship it?"
            }
            """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: payload))
        #expect(event.kind == .turnEnded(awaitsReply: true, liveSubagentCount: 0))
        #expect(event.summary?.text == "Everything is wired. Ship it?")
        // Structured facts still come from the transcript.
        #expect(event.summary?.todosDone == 1)
        #expect(event.summary?.todosTotal == 1)
    }

    @Test("A Stop with a live Sous-agent in background_tasks reports liveSubagentCount 1 (#48)")
    func stopReadsLiveSubagentFromBackgroundTasks() throws {
        let event = try #require(
            ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stopWithLiveSubagent))

        #expect(event.sessionID == "abc123")
        // The constat gates on the count; the crons entry is NOT a subagent.
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 1))
    }

    @Test("A Stop with an empty background_tasks reports liveSubagentCount 0 (#48)")
    func stopWithEmptyBackgroundTasksReportsZero() throws {
        let event = try #require(
            ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stopWithNoLiveSubagent))

        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
    }

    @Test("liveSubagentCount ignores non-subagent entries and blank ids (#48)")
    func liveSubagentCountFiltersByTypeAndId() {
        // A crons-style entry (no type), a foreign type, and a blank id must all
        // be ignored — only genuine Sous-agents count.
        let payload = Data("""
            {
              "session_id": "abc123",
              "hook_event_name": "Stop",
              "last_assistant_message": "Fait.",
              "background_tasks": [
                { "id": "cron-1", "schedule": "0 9 * * *" },
                { "id": "x", "type": "other", "status": "running" },
                { "id": "", "type": "subagent", "status": "running" },
                { "id": "a52ecbfbd42e9f2a5", "type": "subagent", "status": "running" }
              ]
            }
            """.utf8)

        #expect(ClaudeCodeAdapter.liveSubagentCount(fromHookPayload: payload) == 1)
    }

    @Test("A Stop with no background_tasks field at all reports liveSubagentCount 0 (#48)")
    func stopWithoutBackgroundTasksFieldReportsZero() throws {
        // Older builds omit the field; the turn resolves as a plain constat.
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
    }

    @Test("Tool events fired inside a subagent (agent_id present) are ignored")
    func subagentToolEventsAreIgnored() throws {
        // Per the hooks doc, agent_id is present only when the hook fires
        // inside a subagent call: those must never touch the main Session.
        let payload = try #require(String(data: Fixtures.preToolUse, encoding: .utf8))
        let subagentPayload = payload.replacingOccurrences(
            of: #""tool_name": "Bash","#,
            with: #""tool_name": "Bash", "agent_id": "subagent-xyz789", "agent_type": "Explore","#
        )

        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data(subagentPayload.utf8)) == nil)
    }

    @Test("Notification hook payload (permission request) becomes a 'waiting for user' event")
    func notificationBecomesWaitingForUser() throws {
        let fixture = Data("""
        {
          "session_id": "abc123",
          "transcript_path": "/tmp/abc123.jsonl",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Notification",
          "notification_type": "permission_prompt",
          "message": "Claude needs your permission to use Bash"
        }
        """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: fixture))

        #expect(event.sessionID == "abc123")
        #expect(event.kind == .waitingForUser(message: "Claude needs your permission to use Bash"))
    }

    @Test("A blocking Notification reads the transcript and attaches the pending AskUserQuestion")
    func notificationAttachesPendingQuestion() throws {
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-ask-\(UUID().uuidString).jsonl")
        try Data("""
            {"isSidechain":false,"type":"user","message":{"role":"user","content":"Choose"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z"}
            {"isSidechain":false,"type":"assistant","message":{"id":"msg_1","role":"assistant","content":[{"type":"tool_use","id":"toolu_1","name":"AskUserQuestion","input":{"questions":[{"question":"Which sprite direction?","header":"Sprites","multiSelect":false,"options":[{"label":"Bots","description":"d1"},{"label":"Blobs","description":"d2"}]}]}}]},"uuid":"a-1","timestamp":"2026-07-19T10:00:05.000Z"}
            """.utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }

        let payload = Data("""
            {
              "session_id": "abc123",
              "transcript_path": "\(transcript.path)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "Notification",
              "notification_type": "permission_prompt",
              "message": "Claude is asking a question"
            }
            """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: payload))
        #expect(event.kind == .waitingForUser(message: "Claude is asking a question"))
        let question = try #require(event.question)
        #expect(question.prompt == "Which sprite direction?")
        #expect(question.options.map(\.label) == ["Bots", "Blobs"])
    }

    @Test("A blocking Notification with no extractable question still notifies, no buttons (US10)")
    func notificationWithoutQuestionDegrades() throws {
        // A genuine permission prompt: no readable AskUserQuestion transcript, so
        // the event flows without a question (the card degrades to Click-to-focus).
        let fixture = Data("""
            {
              "session_id": "abc123",
              "transcript_path": "/tmp/island-does-not-exist-\(UUID().uuidString).jsonl",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "Notification",
              "notification_type": "permission_prompt",
              "message": "Claude needs your permission to use Bash"
            }
            """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: fixture))
        #expect(event.kind == .waitingForUser(message: "Claude needs your permission to use Bash"))
        #expect(event.question == nil)
    }

    @Test("Informational notifications (auth_success) never put the Session in waiting")
    func informationalNotificationIsIgnored() {
        let fixture = Data("""
        {
          "session_id": "abc123",
          "transcript_path": "/tmp/abc123.jsonl",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Notification",
          "notification_type": "auth_success",
          "message": "Authentication successful"
        }
        """.utf8)

        #expect(ClaudeCodeAdapter.event(fromHookPayload: fixture) == nil)
    }

    @Test("The idle notification (idle_prompt) is non-blocking and never waits")
    func idleNotificationIsNonBlocking() {
        // Root cause A (#31): the ~60 s idle notification fires the Notification
        // hook too, but it must NOT put the Session in "?".
        let fixture = Data("""
        {
          "session_id": "abc123",
          "transcript_path": "/tmp/abc123.jsonl",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Notification",
          "notification_type": "idle_prompt",
          "message": "Claude is waiting for your input"
        }
        """.utf8)

        #expect(ClaudeCodeAdapter.event(fromHookPayload: fixture) == nil)
    }

    @Test("A question notification (elicitation_dialog) becomes a 'waiting for user' event")
    func elicitationDialogBecomesWaitingForUser() throws {
        let fixture = Data("""
        {
          "session_id": "abc123",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Notification",
          "notification_type": "elicitation_dialog",
          "message": "The MCP server needs some information"
        }
        """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: fixture))
        #expect(event.kind == .waitingForUser(message: "The MCP server needs some information"))
    }

    @Test("Notification without a type: a permission message still waits (message fallback)")
    func typelessPermissionNotificationWaits() throws {
        // Older builds may omit notification_type; the adapter then reads the
        // message text (#31): a permission ask still blocks.
        let fixture = Data("""
        {
          "session_id": "abc123",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Notification",
          "message": "Claude needs your permission to use Bash"
        }
        """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: fixture))
        #expect(event.kind == .waitingForUser(message: "Claude needs your permission to use Bash"))
    }

    @Test("Notification without a type: an idle message stays non-blocking (message fallback)")
    func typelessIdleNotificationIsNonBlocking() {
        // The crux of root cause A: a typeless idle notification must NOT be
        // treated as blocking (the old `guard let type else { return true }`).
        let fixture = Data("""
        {
          "session_id": "abc123",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "Notification",
          "message": "Claude is waiting for your input"
        }
        """.utf8)

        #expect(ClaudeCodeAdapter.event(fromHookPayload: fixture) == nil)
    }

    @Test("Events carry the terminal hosting the Session, defaulting to ghostty")
    func eventsCarryDefaultTerminal() throws {
        // The hook payload has no terminal field yet: the adapter (and only
        // the adapter, ADR-0004) supplies the v1 default.
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))

        #expect(event.terminal == "ghostty")
    }

    // MARK: - Session title (issue #32)

    @Test("Any event reads the current title from the transcript (not just Stop), rename wins")
    func eventsCarryTheSessionTitle() throws {
        // /rename writes a custom-title; the auto ai-title stays frozen. The
        // title is read on every event — here a plain PreToolUse — and the
        // manual rename wins, so it is reflected without waiting for the turn.
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("adapter-title-\(UUID().uuidString).jsonl")
        try Data("""
            {"type":"ai-title","aiTitle":"Auto generated title","sessionId":"abc123"}
            {"isSidechain":false,"type":"user","message":{"role":"user","content":"Go"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z"}
            {"type":"custom-title","customTitle":"Renamed session","sessionId":"abc123"}
            """.utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }

        let payload = Data("""
            {
              "session_id": "abc123",
              "transcript_path": "\(transcript.path)",
              "cwd": "/Users/loic/Documents/island",
              "hook_event_name": "PreToolUse",
              "tool_name": "Bash"
            }
            """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: payload))
        #expect(event.kind == .toolStarted(tool: "Bash"))
        #expect(event.title == "Renamed session")
    }

    @Test("Hover refresh re-reads a /rename that fired no hook (#32 regression)")
    func titleRefresherPicksUpRenameWithoutHook() throws {
        // The real failure: rename an idle/ended Session, no further hook fires,
        // so nothing re-reads the transcript. The refresher, triggered on hover,
        // re-reads the remembered transcript and picks up the new custom-title.
        let transcript = FileManager.default.temporaryDirectory
            .appendingPathComponent("refresher-\(UUID().uuidString).jsonl")
        let autoTitle = #"{"type":"ai-title","aiTitle":"Auto generated title","sessionId":"s1"}"#
        try Data(autoTitle.utf8).write(to: transcript)
        defer { try? FileManager.default.removeItem(at: transcript) }

        let refresher = ClaudeCodeTitleRefresher()
        let payload = Data("""
            {"session_id": "s1", "transcript_path": "\(transcript.path)", "hook_event_name": "Stop"}
            """.utf8)
        refresher.observe(hookPayload: payload)
        #expect(refresher.currentTitle(forSessionID: "s1") == "Auto generated title")

        // /rename with no subsequent hook: a custom-title is appended (the auto
        // title stays, as in real transcripts). The refresher must pick it up.
        try Data((autoTitle + "\n"
            + #"{"type":"custom-title","customTitle":"Renamed while idle","sessionId":"s1"}"#).utf8)
            .write(to: transcript)
        #expect(refresher.currentTitle(forSessionID: "s1") == "Renamed while idle")

        // A Session the refresher never saw has no path to re-read.
        #expect(refresher.currentTitle(forSessionID: "unknown") == nil)
    }

    @Test("An unreadable transcript leaves the title nil, and the event still flows")
    func unreadableTranscriptLeavesTitleNil() throws {
        // Fixtures.stop points at a path that does not exist here.
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))
        #expect(event.kind == .turnEnded(awaitsReply: false, liveSubagentCount: 0))
        #expect(event.title == nil)
    }

    @Test("Unreadable payload is ignored instead of crashing")
    func unreadablePayloadIsIgnored() {
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("not json".utf8)) == nil)
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("{}".utf8)) == nil)
    }
}
