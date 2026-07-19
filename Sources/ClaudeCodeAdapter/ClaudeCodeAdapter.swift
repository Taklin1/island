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

    /// Translates a raw hook payload into a generic event.
    ///
    /// - Returns: the generic event, or `nil` when the payload is not valid
    ///   JSON or its `hook_event_name` is not handled by this slice.
    public static func event(fromHookPayload data: Data) -> AgentEvent? {
        guard let payload = try? JSONDecoder().decode(HookPayload.self, from: data) else {
            return nil
        }

        switch payload.hookEventName {
        case "Stop":
            return AgentEvent(
                sessionID: payload.sessionID,
                state: .ended,
                cwd: payload.cwd,
                agent: agentName
            )
        default:
            // SubagentStop (and any future unhandled hook) is deliberately ignored.
            return nil
        }
    }

    /// Subset of the Claude Code hook stdin payload this slice cares about.
    /// See https://code.claude.com/docs/en/hooks (common input fields).
    private struct HookPayload: Decodable {
        let sessionID: String
        let hookEventName: String
        let cwd: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case hookEventName = "hook_event_name"
            case cwd
        }
    }
}
