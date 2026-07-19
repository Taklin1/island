import Foundation
import IslandStore

/// Translates raw Claude Code hook payloads (ADR-0001) into generic
/// ``AgentEvent`` values (ADR-0004).
///
/// Everything specific to Claude Code (hook JSON shape, event names) stays
/// behind this boundary. Payloads that carry no meaning for Island — such as
/// `SubagentStop` — translate to `nil` and are silently ignored upstream.
public enum ClaudeCodeAdapter {
    /// Name reported in generic events for sessions driven by Claude Code.
    public static let agentName = "claude-code"

    /// Terminal reported on every event. The hook payload carries no terminal
    /// information yet, so the adapter supplies the v1 default (ADR-0004:
    /// tool-specific defaults never leak past the adapter).
    public static let defaultTerminal = "ghostty"

    /// Translates a raw hook payload into a generic event.
    ///
    /// - Returns: the generic event, or `nil` when the payload is not valid
    ///   JSON or its `hook_event_name` is not handled by this slice.
    public static func event(fromHookPayload data: Data) -> AgentEvent? {
        guard let payload = try? JSONDecoder().decode(HookPayload.self, from: data) else {
            return nil
        }

        // Hooks fired inside a subagent carry an agent_id; subagents never
        // create or drive a Session (only the main conversation does).
        guard payload.agentID == nil else { return nil }

        let kind: AgentEventKind
        var summary: TurnSummary?
        switch payload.hookEventName {
        case "SessionStart":
            kind = .sessionStarted
        case "SessionEnd":
            kind = .sessionEnded
        case "UserPromptSubmit":
            guard let prompt = payload.prompt else { return nil }
            kind = .promptSubmitted(prompt: prompt)
        case "PreToolUse":
            guard let tool = payload.toolName else { return nil }
            kind = .toolStarted(tool: tool)
        case "PostToolUse":
            guard let tool = payload.toolName else { return nil }
            kind = .toolFinished(tool: tool)
        case "Stop":
            kind = .turnEnded
            // ADR-0002: summarize the turn by local extraction from the
            // transcript. Best-effort only — on any failure the event still
            // flows without a summary (fallback: state + project).
            if let path = payload.transcriptPath {
                summary = TranscriptReader.summary(
                    ofTranscriptAt: URL(fileURLWithPath: path))
            }
        case "Notification":
            // Only notifications that actually block on the user (permission
            // request, question) put the Session in waiting; informational
            // ones (auth_success…) are ignored.
            guard isWaitingNotification(payload.notificationType) else { return nil }
            kind = .waitingForUser(message: payload.message)
        default:
            // SubagentStart/SubagentStop (and any future unhandled hook) are
            // deliberately ignored.
            return nil
        }

        return AgentEvent(
            sessionID: payload.sessionID,
            kind: kind,
            cwd: payload.cwd,
            terminal: defaultTerminal,
            agent: agentName,
            summary: summary
        )
    }

    /// Subset of the Claude Code hook stdin payload this slice cares about.
    /// See https://code.claude.com/docs/en/hooks (common input fields).
    private struct HookPayload: Decodable {
        let sessionID: String
        let hookEventName: String
        let transcriptPath: String?
        let cwd: String?
        let prompt: String?
        let toolName: String?
        /// Present only when the hook fires inside a subagent call.
        let agentID: String?
        /// Notification hook only: human-readable notification text.
        let message: String?
        /// Notification hook only: e.g. "permission_prompt", "idle_prompt".
        let notificationType: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case hookEventName = "hook_event_name"
            case transcriptPath = "transcript_path"
            case cwd
            case prompt
            case toolName = "tool_name"
            case agentID = "agent_id"
            case message
            case notificationType = "notification_type"
        }
    }

    /// Whether a Notification actually blocks on the user. Unknown or absent
    /// types are treated as blocking: better a Liseré to acknowledge than a
    /// stuck agent nobody notices.
    private static func isWaitingNotification(_ type: String?) -> Bool {
        guard let type else { return true }
        let nonBlocking: Set<String> = [
            "auth_success", "elicitation_complete", "elicitation_response",
            "agent_completed",
        ]
        return !nonBlocking.contains(type)
    }
}
