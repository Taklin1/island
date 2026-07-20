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

        // Any hook fired inside a subagent (agent_id present) is ignored: only
        // the main conversation drives a Session's lifecycle. This is what makes
        // background subagents safe — a real turn spawning a Sous-agent (the
        // `Agent` tool) has all of the subagent's tool hooks carry an agent_id;
        // they are dropped here and never touch the parent. The parent's live
        // Sous-agents are instead read from the Stop's `background_tasks` list
        // (#48, ADR-0008 amended), not from these scattered hooks. (The
        // SubagentStart/SubagentStop hooks are never installed, so a real
        // Sous-agent emits none — they fall through to the unhandled default.)
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
            // ADR-0002: summarize the turn by local extraction from the
            // transcript (todos, files, duration, and the last message text).
            // Best-effort only — on any failure the event still flows without a
            // summary (fallback: state + project).
            if let path = payload.transcriptPath {
                summary = TranscriptReader.summary(
                    ofTranscriptAt: URL(fileURLWithPath: path))
            }
            // The transcript file LAGS at Stop time: Claude Code's hooks docs
            // warn it "might not yet include the current turn's most recent
            // messages", and recommend using `last_assistant_message` from the
            // payload for the final assistant text. That field is authoritative
            // and race-free, so it wins over the (possibly stale) transcript
            // text; the transcript still provides the structured facts. Older
            // builds omit it → we keep the transcript text (#39, real repro).
            if let message = payload.lastAssistantMessage, !message.isEmpty {
                summary = TurnSummary(
                    text: message,
                    todosDone: summary?.todosDone,
                    todosTotal: summary?.todosTotal,
                    filesModified: summary?.filesModified ?? [],
                    turnDuration: summary?.turnDuration
                )
            }
            // #39 / ADR-0006: a turn whose last assistant message ends on a
            // question ("?") is "attend", not "terminé". Detect it on that
            // verbatim final text (right-trimmed). No interrogative-word scan
            // (false positives); no signal (nil/empty text) ⇒ not a question.
            // #48 / ADR-0008 amended: also read how many Sous-agents are still
            // live at this Stop from `background_tasks`, so the store can gate a
            // constat to `.running` without a race or a clock tick.
            kind = .turnEnded(
                awaitsReply: lastMessageIsQuestion(summary?.text),
                liveSubagentCount: liveSubagentCount(fromHookPayload: data))
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

        // Session title (issue #32): re-read on every main event, not just Stop
        // — a /rename does not always fire a hook, so the current title is
        // picked up from the transcript at the next event of any kind. Cheap
        // bounded tail read; nil on any failure (fallback: project folder name).
        let title = payload.transcriptPath.flatMap {
            TranscriptReader.title(ofTranscriptAt: URL(fileURLWithPath: $0))
        }

        return event(payload, kind: kind, summary: summary, title: title)
    }

    /// Builds a generic event from a decoded payload, filling in the v1
    /// terminal/agent defaults (ADR-0004).
    private static func event(
        _ payload: HookPayload, kind: AgentEventKind,
        summary: TurnSummary? = nil, title: String? = nil
    ) -> AgentEvent {
        AgentEvent(
            sessionID: payload.sessionID,
            kind: kind,
            cwd: payload.cwd,
            terminal: defaultTerminal,
            agent: agentName,
            summary: summary,
            title: title
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
        /// Stop hook only: the verbatim final assistant message of the turn.
        /// Claude Code hands it in the payload precisely because the transcript
        /// file may lag at Stop time — it is the authoritative, race-free source
        /// for the final text (#39). Absent on older builds.
        let lastAssistantMessage: String?
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
            case lastAssistantMessage = "last_assistant_message"
            case message
            case notificationType = "notification_type"
        }
    }

    /// How many **Sous-agents** are still running at this Stop, read from the
    /// hook's `background_tasks` list (issue #48, ADR-0008 amended). Ground
    /// truth from the targeted capture: a Stop while a background `Agent`
    /// subagent runs carries an entry `{ id, type: "subagent", status, … }`
    /// whose `id` is the subagent's agent_id; once it finishes, the list is
    /// empty. Only entries that are genuinely a Sous-agent count —
    /// `type == "subagent"` **and** a non-empty `id` — so a `session_crons`
    /// entry or a blank id is never mistaken for one.
    ///
    /// `background_tasks` is a **JSON array** on the wire (Codable-decodable);
    /// the plist-looking rendering seen while capturing was only an artifact of
    /// logging a parsed `NSArray`. Parsing is deliberately lenient: any decode
    /// failure or unexpected shape yields **0**, so a Stop is never dropped and
    /// the Session simply resolves as it did before the gate — a wrong count is
    /// caught loudly by the real-hook FP (the card would go green during a
    /// subagent), never masked into a crash.
    static func liveSubagentCount(fromHookPayload data: Data) -> Int {
        guard let envelope = try? JSONDecoder().decode(BackgroundTasksEnvelope.self, from: data)
        else { return 0 }
        return (envelope.backgroundTasks ?? []).filter { task in
            task.type == "subagent" && !(task.id ?? "").isEmpty
        }.count
    }

    /// Minimal Codable view of just the `background_tasks` list, decoded
    /// separately from ``HookPayload`` so its parsing stays lenient (a
    /// surprising shape never fails the whole payload decode).
    private struct BackgroundTasksEnvelope: Decodable {
        let backgroundTasks: [BackgroundTask]?
        enum CodingKeys: String, CodingKey {
            case backgroundTasks = "background_tasks"
        }
    }

    /// One entry of `background_tasks`. Only `id`/`type` matter for the gate;
    /// every other field (`status`, `agent_type`, `description`…) is ignored.
    private struct BackgroundTask: Decodable {
        let id: String?
        let type: String?
    }

    /// Whether the turn's last assistant message ends on a question (#39,
    /// ADR-0006). The rule is deliberately narrow: the verbatim text, trimmed
    /// of surrounding whitespace/newlines, must end with `?`. No scan for
    /// interrogative words (too many false positives), and no text at all
    /// (extraction failed, or the turn produced no prose) means "not a
    /// question" — the store then treats the turn as `.ended` (green), never
    /// crying "attend" without a signal.
    private static func lastMessageIsQuestion(_ text: String?) -> Bool {
        guard let text else { return false }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("?")
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
