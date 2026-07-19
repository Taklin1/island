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

    @Test("SubagentStop hook payload is ignored")
    func subagentStopIsIgnored() {
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.subagentStop) == nil)
    }

    @Test("SubagentStart hook payload is ignored")
    func subagentStartIsIgnored() {
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

        #expect(ClaudeCodeAdapter.event(fromHookPayload: fixture) == nil)
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

    @Test("Unreadable payload is ignored instead of crashing")
    func unreadablePayloadIsIgnored() {
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("not json".utf8)) == nil)
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("{}".utf8)) == nil)
    }
}
