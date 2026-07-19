import Foundation

/// A Claude-agnostic view of one live agent conversation.
public struct Session: Identifiable, Equatable, Sendable {
    /// Stable identifier (the adapter guarantees uniqueness per conversation).
    public let id: String
    /// Current lifecycle state.
    public var state: SessionState
    /// Working directory of the session, when known.
    public var cwd: String?
    /// Session title, when the adapter could extract one (issue #32, e.g. the
    /// Claude Code `ai-title`). `nil` until a title is known; the UI then falls
    /// back to ``projectName``. Reflects `/rename`: the store keeps the latest
    /// title an event carried.
    public var title: String?
    /// Which agent tool drives this session (e.g. "claude-code").
    public let agent: String
    /// Terminal hosting the session (e.g. "ghostty"), when known.
    public var terminal: String?
    /// Last prompt the user submitted, when known.
    public var lastPrompt: String?
    /// Tool currently running, when the agent is inside a tool call.
    public var currentTool: String?
    /// When the current turn started (for the elapsed-time display).
    public var turnStartedAt: Date?
    /// Summary of the last finished turn (ADR-0002), when extraction worked.
    /// Cleared as soon as a new prompt starts the next turn.
    public var lastSummary: TurnSummary?
    /// Last time any event touched this session (drives orphan expiry).
    public var lastActivityAt: Date
    /// True while a marking event (waiting / turn ended) has not been
    /// Acknowledged by the user. Drives the Liseré.
    public var needsAcknowledgement: Bool
    /// Subagents currently running under this Session (issue #31). A Session
    /// with a live subagent is never shown "terminée": its turn is not done.
    public var activeSubagentCount: Int
    /// Whether the main turn's Stop hook has fired for the current turn. The
    /// Session only becomes `.ended` once this is true *and* no subagent is
    /// still running — a SubagentStop can arrive after the main Stop (#31).
    public var mainTurnFinished: Bool

    /// Human-readable project name: last path component of the cwd.
    public var projectName: String {
        guard let cwd, !cwd.isEmpty else { return "session" }
        return URL(fileURLWithPath: cwd).lastPathComponent
    }

    public init(
        id: String,
        state: SessionState,
        cwd: String? = nil,
        title: String? = nil,
        agent: String,
        terminal: String? = nil,
        lastPrompt: String? = nil,
        currentTool: String? = nil,
        turnStartedAt: Date? = nil,
        lastSummary: TurnSummary? = nil,
        lastActivityAt: Date = Date(),
        needsAcknowledgement: Bool = false,
        activeSubagentCount: Int = 0,
        mainTurnFinished: Bool = false
    ) {
        self.id = id
        self.state = state
        self.cwd = cwd
        self.title = title
        self.agent = agent
        self.terminal = terminal
        self.lastPrompt = lastPrompt
        self.currentTool = currentTool
        self.turnStartedAt = turnStartedAt
        self.lastSummary = lastSummary
        self.lastActivityAt = lastActivityAt
        self.needsAcknowledgement = needsAcknowledgement
        self.activeSubagentCount = activeSubagentCount
        self.mainTurnFinished = mainTurnFinished
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

        let existing = sessions.first(where: { $0.id == event.sessionID })
        // Subagent bookkeeping targets the PARENT Session and never creates one
        // (#31): a subagent event for a Session we don't track is dropped.
        if existing == nil,
            event.kind == .subagentStarted || event.kind == .subagentStopped {
            return
        }

        var session = existing
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
        if let terminal = event.terminal {
            session.terminal = terminal
        }
        // Title (issue #32): keep the latest one an event carried, and never
        // clear a known title when a later event could not read one — so a
        // /rename is reflected while a titleless event leaves it untouched.
        if let title = event.title {
            session.title = title
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
            session.needsAcknowledgement = false
            session.lastSummary = nil
            // A new prompt is a fresh turn: the previous main Stop no longer
            // counts against the subagents still being tracked (#31).
            session.mainTurnFinished = false
        case let .toolStarted(tool):
            session.state = .running
            session.currentTool = tool
            session.needsAcknowledgement = false
            if session.turnStartedAt == nil {
                session.turnStartedAt = timestamp
            }
        case .toolFinished:
            session.currentTool = nil
        case .turnEnded:
            // The main turn's Stop fired. But it is only "terminée" once every
            // subagent has stopped too — a Stop with subagents in flight keeps
            // the Session "en cours" (root cause C, #31).
            session.currentTool = nil
            session.lastSummary = event.summary
            session.mainTurnFinished = true
            if session.activeSubagentCount > 0 {
                session.state = .running
            } else {
                session.state = .ended
                session.turnStartedAt = nil
                session.needsAcknowledgement = true
            }
        case .subagentStarted:
            // Subagents never create a Session (guarded above); they bump the
            // parent's count and keep it working, never "terminée" (#31).
            session.activeSubagentCount += 1
            if session.state == .idle || session.state == .ended {
                session.state = .running
                session.needsAcknowledgement = false
                session.mainTurnFinished = false
            }
        case .subagentStopped:
            session.activeSubagentCount = max(0, session.activeSubagentCount - 1)
            if session.activeSubagentCount == 0,
                session.mainTurnFinished,
                session.state == .running {
                // Last subagent gone and the main turn already ended: only now
                // is the turn truly finished — this Stop may arrive after the
                // main one (#31). Guarded to `.running` so it never clobbers a
                // genuine block ("?") that appeared during the wrap-up.
                session.state = .ended
                session.currentTool = nil
                session.turnStartedAt = nil
                session.needsAcknowledgement = true
            }
        case .waitingForUser:
            // Root cause B (#31): a genuine block moves the Session to waiting
            // from any live state, but never resurrects a turn that already
            // ended — a real permission/question never follows a finished turn,
            // so a stray notification must not turn a "terminé" back into "?".
            if session.state != .ended {
                session.state = .waiting
                session.needsAcknowledgement = true
            }
        }

        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.append(session)
        }
    }

    // MARK: - Title refresh (issue #32)

    /// Updates a known Session's title out of band — used by the Extended-hover
    /// refresh to reflect a `/rename` that fired no hook (an idle/ended Session
    /// gets no further event to re-read its transcript). No-op for an unknown
    /// Session or an unchanged title, so it never publishes needlessly.
    public func setTitle(_ title: String, forSessionID id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }),
            sessions[index].title != title
        else { return }
        sessions[index].title = title
    }

    // MARK: - Acknowledgement (issues #8 / #10)

    /// Hovering the Island acknowledges every pending Session at once.
    public func acknowledgeAll() {
        acknowledge { _ in true }
    }

    /// Clicking a card (or its Peek) acknowledges that one Session.
    public func acknowledge(sessionID: String) {
        acknowledge { $0.id == sessionID }
    }

    /// Focusing a terminal acknowledges the Sessions it hosts.
    public func acknowledge(terminal: String) {
        acknowledge { $0.terminal == terminal }
    }

    /// Clears the flag without ever touching the Session state itself: a
    /// waiting Session stays waiting, only the Liseré goes out.
    private func acknowledge(where matches: (Session) -> Bool) {
        var changed = false
        var updated = sessions
        for index in updated.indices where updated[index].needsAcknowledgement && matches(updated[index]) {
            updated[index].needsAcknowledgement = false
            changed = true
        }
        // Publish once, and only when something actually changed.
        if changed {
            sessions = updated
        }
    }
}
