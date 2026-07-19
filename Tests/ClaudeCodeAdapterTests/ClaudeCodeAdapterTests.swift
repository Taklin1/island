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

    static let subagentStop = Data("""
    {
      "session_id": "abc123",
      "transcript_path": "/Users/loic/.claude/projects/-Users-loic-Documents-island/abc123.jsonl",
      "cwd": "/Users/loic/Documents/island",
      "permission_mode": "default",
      "hook_event_name": "SubagentStop",
      "agent_id": "subagent-xyz789",
      "agent_type": "Explore",
      "last_assistant_message": "Exploration complete."
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

    @Test("Stop hook payload becomes a generic 'turn ended' event")
    func stopPayloadBecomesEndedEvent() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))

        #expect(event.sessionID == "abc123")
        #expect(event.kind == .turnEnded)
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
        #expect(event.kind == .turnEnded)
        #expect(event.summary?.text == "Shipped: the release is tagged.")
        #expect(event.summary?.turnDuration == 42)
    }

    @Test("Stop with an unreadable transcript still emits the event (fallback)")
    func stopWithUnreadableTranscriptStillNotifies() throws {
        // ADR-0002: the notification must always go out; a missing transcript
        // only means no summary.
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))
        #expect(event.kind == .turnEnded)
        #expect(event.summary == nil)
    }

    @Test("SubagentStop becomes a 'subagent stopped' event on the PARENT session")
    func subagentStopBecomesSubagentStopped() throws {
        // The payload carries an agent_id, yet it targets the parent session_id
        // (#31): it decrements the parent's count, it never creates a Session.
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.subagentStop))

        #expect(event.sessionID == "abc123")
        #expect(event.kind == .subagentStopped)
    }

    @Test("SubagentStart becomes a 'subagent started' event on the PARENT session")
    func subagentStartBecomesSubagentStarted() throws {
        let fixture = Data("""
        {
          "session_id": "abc123",
          "transcript_path": "/tmp/abc123.jsonl",
          "cwd": "/Users/loic/Documents/island",
          "hook_event_name": "SubagentStart",
          "agent_id": "subagent-xyz789",
          "agent_type": "Explore"
        }
        """.utf8)

        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: fixture))

        #expect(event.sessionID == "abc123")
        #expect(event.kind == .subagentStarted)
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

    @Test("Unreadable payload is ignored instead of crashing")
    func unreadablePayloadIsIgnored() {
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("not json".utf8)) == nil)
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("{}".utf8)) == nil)
    }
}
