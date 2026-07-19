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

    public init(
        sessionID: String,
        kind: AgentEventKind,
        cwd: String? = nil,
        terminal: String? = nil,
        agent: String
    ) {
        self.sessionID = sessionID
        self.kind = kind
        self.cwd = cwd
        self.terminal = terminal
        self.agent = agent
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
}
