import Foundation

/// A Claude-agnostic view of one live agent conversation.
public struct Session: Identifiable, Equatable, Sendable {
    /// Stable identifier (the adapter guarantees uniqueness per conversation).
    public let id: String
    /// Current lifecycle state.
    public var state: SessionState
    /// Working directory of the session, when known.
    public var cwd: String?
    /// Which agent tool drives this session (e.g. "claude-code").
    public let agent: String

    /// Human-readable project name: last path component of the cwd.
    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "session" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    public init(id: String, state: SessionState, cwd: String? = nil, agent: String) {
        self.id = id
        self.state = state
        self.cwd = cwd
        self.agent = agent
    }
}

/// Publishes the state of all known Sessions from the stream of generic
/// events. Main-actor bound: the UI observes it directly.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [Session] = []

    public init() {}

    /// Applies one generic event: updates the matching Session or creates it.
    public func apply(_ event: AgentEvent) {
        if let index = sessions.firstIndex(where: { $0.id == event.sessionID }) {
            sessions[index].state = event.state
            if let cwd = event.cwd {
                sessions[index].cwd = cwd
            }
        } else {
            sessions.append(Session(
                id: event.sessionID,
                state: event.state,
                cwd: event.cwd,
                agent: event.agent
            ))
        }
    }
}
