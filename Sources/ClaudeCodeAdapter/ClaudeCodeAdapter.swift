import Foundation
import IslandStore

/// Translates raw Claude Code hook payloads (ADR-0001) into generic
/// ``AgentEvent`` values (ADR-0004).
///
/// Everything specific to Claude Code (hook JSON shape, event names) stays
/// behind this boundary. Payloads that carry no meaning for Island — an
/// unhandled hook, or a tool hook fired inside a subagent — translate to `nil`
/// and are silently ignored upstream.
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

        // SubagentStart/SubagentStop carry the PARENT session_id *and* an
        // agent_id; they never create a Session, they bump the parent's
        // active-subagent count (#31). Handle them before the agent_id guard
        // below, which drops the OTHER hooks fired inside a subagent.
        switch payload.hookEventName {
        case "SubagentStart":
            return event(payload, kind: .subagentStarted)
        case "SubagentStop":
            return event(payload, kind: .subagentStopped)
        default:
            break
        }

        // Any other hook fired inside a subagent (agent_id present) is ignored:
        // only the main conversation drives a Session's lifecycle.
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
            // request, question) put the Session in waiting; the idle
            // notification and informational ones are ignored (#31).
            guard isWaitingNotification(type: payload.notificationType, message: payload.message)
            else { return nil }
            kind = .waitingForUser(message: payload.message)
        default:
            // Any future unhandled hook is deliberately ignored.
            return nil
        }

        return event(payload, kind: kind, summary: summary)
    }

    /// Builds a generic event from a decoded payload, filling in the v1
    /// terminal/agent defaults (ADR-0004).
    private static func event(
        _ payload: HookPayload, kind: AgentEventKind, summary: TurnSummary? = nil
    ) -> AgentEvent {
        AgentEvent(
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
        /// Notification hook only. Claude Code's Notification types include
        /// `permission_prompt`, `idle_prompt`, `auth_success`,
        /// `elicitation_dialog`/`_complete`/`_response`, `agent_needs_input`
        /// and `agent_completed`. The field may be absent on older builds, so
        /// the adapter also reads the `message` as a fallback (#31).
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

    /// Whether a Notification actually blocks on the user — a permission
    /// request or a question the agent cannot proceed without. Only those put
    /// the Session in waiting ("?"); everything else, and notably the ~60 s
    /// idle notification (`idle_prompt`), is non-blocking and must never mark
    /// the Session (#31, root cause A).
    ///
    /// When the notification type is present we trust it: only the genuinely
    /// blocking types wait. When it is absent we fall back to the message text
    /// and default to non-blocking — a Notification we cannot positively read
    /// as a permission/question must not raise a false "?" (this reverses the
    /// old "unknown ⇒ blocking" default, which let idle resurrect Sessions).
    private static func isWaitingNotification(type: String?, message: String?) -> Bool {
        if let type {
            let blocking: Set<String> = [
                "permission_prompt", "elicitation_dialog", "agent_needs_input",
            ]
            return blocking.contains(type)
        }
        // No type: only a message that clearly asks for permission/approval
        // blocks. Idle ("waiting for your input") and the rest do not.
        guard let message = message?.lowercased() else { return false }
        return message.contains("permission") || message.contains("approve")
    }
}
