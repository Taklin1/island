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
}

struct ClaudeCodeAdapterTests {
    @Test("Stop hook payload becomes a generic 'ended' event")
    func stopPayloadBecomesEndedEvent() throws {
        let event = try #require(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.stop))

        #expect(event.sessionID == "abc123")
        #expect(event.state == .ended)
        #expect(event.cwd == "/Users/loic/Documents/island")
        #expect(event.agent == "claude-code")
    }

    @Test("SubagentStop hook payload is ignored")
    func subagentStopIsIgnored() {
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Fixtures.subagentStop) == nil)
    }

    @Test("Unreadable payload is ignored instead of crashing")
    func unreadablePayloadIsIgnored() {
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("not json".utf8)) == nil)
        #expect(ClaudeCodeAdapter.event(fromHookPayload: Data("{}".utf8)) == nil)
    }
}
