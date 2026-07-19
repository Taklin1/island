import Foundation

/// What the Island shows of a finished turn (ADR-0002): facts extracted
/// locally by an adapter from its own artifacts (e.g. the Claude Code
/// transcript), never produced by an LLM call. Every field is optional —
/// extraction is best-effort and the event must flow even when it fails.
public struct TurnSummary: Equatable, Sendable {
    /// Last assistant message of the main turn, verbatim.
    public let text: String?
    /// Completed todos at the end of the turn, when the agent kept a list.
    public let todosDone: Int?
    /// Total todos at the end of the turn, when the agent kept a list.
    public let todosTotal: Int?
    /// Files the agent modified during the turn (absolute paths, in order).
    public let filesModified: [String]
    /// Wall-clock duration of the turn, when both ends could be timestamped.
    public let turnDuration: TimeInterval?

    public init(
        text: String? = nil,
        todosDone: Int? = nil,
        todosTotal: Int? = nil,
        filesModified: [String] = [],
        turnDuration: TimeInterval? = nil
    ) {
        self.text = text
        self.todosDone = todosDone
        self.todosTotal = todosTotal
        self.filesModified = filesModified
        self.turnDuration = turnDuration
    }
}

/// Generic event schema (ADR-0004).
///
/// The store and the UI only ever see this vocabulary; anything specific to a
/// given agent tool (hook formats, transcripts…) lives in its adapter.
public struct AgentEvent: Equatable, Sendable {
    /// Stable identifier of the Session this event belongs to.
    public let sessionID: String
    /// What happened to the Session.
    public let kind: AgentEventKind
    /// Working directory of the Session (used to derive the project name).
    public let cwd: String?
    /// Terminal hosting the Session, when known.
    public let terminal: String?
    /// Which agent tool produced the event (e.g. "claude-code").
    public let agent: String
    /// What the turn produced, extracted locally by the adapter (ADR-0002).
    /// Only meaningful on `.turnEnded`; `nil` when extraction failed — the
    /// event still flows (fallback: state + project).
    public let summary: TurnSummary?

    public init(
        sessionID: String,
        kind: AgentEventKind,
        cwd: String? = nil,
        terminal: String? = nil,
        agent: String,
        summary: TurnSummary? = nil
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.cwd = cwd
        self.terminal = terminal
        self.agent = agent
        self.summary = summary
    }
}

/// Session lifecycle facts, agent-agnostic. Adapters translate their native
/// events (hooks…) into these; the store turns them into Session state.
public enum AgentEventKind: Equatable, Sendable {
    /// The Session appeared (or resumed — the store upserts, never duplicates).
    case sessionStarted
    /// The user submitted a prompt: the Session starts working on a turn.
    case promptSubmitted(prompt: String)
    /// The agent is about to run a tool.
    case toolStarted(tool: String)
    /// The tool finished; the agent keeps working on the turn.
    case toolFinished(tool: String)
    /// The agent finished its turn (the Session stays alive, idle).
    case turnEnded
    /// The agent is blocked on the user (permission request or question).
    case waitingForUser(message: String?)
    /// The Session closed for good: it disappears from the Island.
    case sessionEnded
}

/// Lifecycle state of a live Session. Closed Sessions are not a state: they
/// are removed from the store altogether.
public enum SessionState: Equatable, Sendable {
    /// Alive but not working (just started, or resumed).
    case idle
    /// Working on a turn (prompt submitted, tools running).
    case running
    /// Turn finished (the "agent done" state the Peek announces).
    case ended
    /// Blocked on the user: permission request or question ("attend").
    case waiting
}
