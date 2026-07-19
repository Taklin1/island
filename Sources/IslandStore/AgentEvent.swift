/// Generic event schema (ADR-0004).
///
/// The store and the UI only ever see this vocabulary; anything specific to a
/// given agent tool (hook formats, transcripts…) lives in its adapter.
public struct AgentEvent: Equatable, Sendable {
    /// Stable identifier of the Session this event belongs to.
    public let sessionID: String
    /// The Session state this event carries.
    public let state: SessionState
    /// Working directory of the Session (used to derive the project name).
    public let cwd: String?
    /// Terminal hosting the Session, when known.
    public let terminal: String?
    /// Which agent tool produced the event (e.g. "claude-code").
    public let agent: String

    public init(
        sessionID: String,
        state: SessionState,
        cwd: String? = nil,
        terminal: String? = nil,
        agent: String
    ) {
        self.sessionID = sessionID
        self.state = state
        self.cwd = cwd
        self.terminal = terminal
        self.agent = agent
    }
}

/// Minimal Session lifecycle for the tracer bullet: active or ended.
public enum SessionState: Equatable, Sendable {
    case active
    case ended
}
