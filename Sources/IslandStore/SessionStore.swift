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
    /// Last prompt the user submitted, when known.
    public var lastPrompt: String?
    /// Tool currently running, when the agent is inside a tool call.
    public var currentTool: String?
    /// When the current turn started (for the elapsed-time display).
    public var turnStartedAt: Date?
    /// Last time any event touched this session (drives orphan expiry).
    public var lastActivityAt: Date

    /// Human-readable project name: last path component of the cwd.
    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "session" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    public init(
        id: String,
        state: SessionState,
        cwd: String? = nil,
        agent: String,
        lastPrompt: String? = nil,
        currentTool: String? = nil,
        turnStartedAt: Date? = nil,
        lastActivityAt: Date = Date()
    ) {
        self.id = id
        self.state = state
        self.cwd = cwd
        self.agent = agent
        self.lastPrompt = lastPrompt
        self.currentTool = currentTool
        self.turnStartedAt = turnStartedAt
        self.lastActivityAt = lastActivityAt
    }
}

/// Publishes the state of all known Sessions from the stream of generic
/// events. Main-actor bound: the UI observes it directly.
@MainActor
public final class SessionStore: ObservableObject {
    @Published public private(set) var sessions: [Session] = []

    private let now: () -> Date
    private let inactivityTTL: TimeInterval
    private var sweepTask: Task<Void, Never>?

    /// - Parameters:
    ///   - now: injectable clock (tests use a fake one).
    ///   - inactivityTTL: how long a silent Session stays on the Island before
    ///     being considered an orphan (crash without SessionEnd) and expired.
    ///   - sweepInterval: how often the store checks for orphans on its own;
    ///     `nil` disables the automatic sweep (tests purge explicitly).
    public init(
        now: @escaping () -> Date = Date.init,
        inactivityTTL: TimeInterval = 30 * 60,
        sweepInterval: Duration? = .seconds(60)
    ) {
        self.now = now
        self.inactivityTTL = inactivityTTL

        if let sweepInterval {
            sweepTask = Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: sweepInterval)
                    guard let self else { return }
                    self.purgeExpiredSessions()
                }
            }
        }
    }

    deinit {
        sweepTask?.cancel()
    }

    /// Drops orphan Sessions: no event for longer than the inactivity TTL.
    /// Called periodically by the store itself, and on every applied event.
    public func purgeExpiredSessions() {
        let deadline = now().addingTimeInterval(-inactivityTTL)
        let expired = sessions.filter { $0.lastActivityAt < deadline }
        guard !expired.isEmpty else { return }
        sessions.removeAll { session in expired.contains { $0.id == session.id } }
    }

    /// Applies one generic event: updates the matching Session or creates it.
    public func apply(_ event: AgentEvent) {
        purgeExpiredSessions()
        let timestamp = now()

        if event.kind == .sessionEnded {
            sessions.removeAll { $0.id == event.sessionID }
            return
        }

        var session = sessions.first(where: { $0.id == event.sessionID })
            ?? Session(
                id: event.sessionID,
                state: .idle,
                cwd: event.cwd,
                agent: event.agent,
                lastActivityAt: timestamp
            )

        if let cwd = event.cwd {
            session.cwd = cwd
        }
        session.lastActivityAt = timestamp

        switch event.kind {
        case .sessionStarted, .sessionEnded:
            // sessionStarted on a known session is a resume: upsert only.
            // (sessionEnded was handled above.)
            break
        case let .promptSubmitted(prompt):
            session.state = .running
            session.lastPrompt = prompt
            session.currentTool = nil
            session.turnStartedAt = timestamp
        case let .toolStarted(tool):
            session.state = .running
            session.currentTool = tool
            if session.turnStartedAt == nil {
                session.turnStartedAt = timestamp
            }
        case .toolFinished:
            session.currentTool = nil
        case .turnEnded:
            session.state = .ended
            session.currentTool = nil
            session.turnStartedAt = nil
        }

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }
}
