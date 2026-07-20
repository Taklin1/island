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
    /// Sous-agents still running under this Session at its last Stop (issues
    /// #31/#48). Read from the Stop's `background_tasks` list (ADR-0008
    /// amended): a Session with a live Sous-agent is never shown "terminée" —
    /// its turn is not done — and the count feeds the discreet tally on the
    /// Extended card (Q6). Reset to zero when a new turn starts.
    public var activeSubagentCount: Int
    /// The AskUserQuestion this Session is blocked on (issue #26), extracted
    /// locally from the transcript. Set only while `.waiting` on an extractable
    /// question; cleared on any transition away from waiting so an answered
    /// question is never re-shown. `nil` = no buttons (Click-to-focus, US10).
    public var pendingQuestion: PendingQuestion?
    /// The human-readable ask of a *buttonless* block (issue #29): the message
    /// the blocking Notification carried — e.g. "Claude needs your permission to
    /// use Bash" for an escalated permission prompt, whose options are not
    /// extractable (spike #25). Set only while `.waiting` **without** a
    /// ``pendingQuestion``, so the card can say WHAT is blocking even when it
    /// shows no buttons; display only, never a decision (US7). Cleared on any
    /// transition away from waiting, exactly like ``pendingQuestion``. `nil`
    /// whenever buttons are shown, or the Notification carried no message.
    public var waitingMessage: String?

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
        pendingQuestion: PendingQuestion? = nil,
        waitingMessage: String? = nil
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
        self.pendingQuestion = pendingQuestion
        self.waitingMessage = waitingMessage
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
            // A new prompt is a fresh turn: any Sous-agent tally from the
            // previous turn's Stop is stale (#48). The next Stop re-reads the
            // live list from `background_tasks`.
            session.activeSubagentCount = 0
            // A resolved AskUserQuestion never lingers into the next turn (#26);
            // nor does a buttonless block's ask (#29).
            session.pendingQuestion = nil
            session.waitingMessage = nil
        case let .toolStarted(tool):
            session.state = .running
            session.currentTool = tool
            session.needsAcknowledgement = false
            session.pendingQuestion = nil
            session.waitingMessage = nil
            if session.turnStartedAt == nil {
                session.turnStartedAt = timestamp
            }
        case .toolFinished:
            session.currentTool = nil
        case let .turnEnded(awaitsReply, liveSubagentCount):
            // The main turn's Stop fired, carrying the live Sous-agent tally
            // read from `background_tasks` at this exact Stop (#48, ADR-0008
            // amended). Resolution, race-free (the count is in the payload):
            //   • a question wins immediately — orange, even with a Sous-agent
            //     still live (Q5, #39 non-regression);
            //   • otherwise a constat stays "en cours" while a Sous-agent runs
            //     (the gate) and only ends once a later Stop reports zero.
            // Every Sous-agent completion injects a fresh main turn ⇒ a fresh
            // Stop, so the gate always re-resolves on an event — no clock tick.
            session.currentTool = nil
            session.lastSummary = event.summary
            session.activeSubagentCount = liveSubagentCount
            // A turn ending on a question (#39/ADR-0006) resolves to waiting via
            // its prose in `lastSummary`, never through a structured
            // AskUserQuestion tool — so any pending one is cleared here whatever
            // the resolution branch (#26): the Stop path carries no options.
            // A buttonless block's ask (#29) does not survive the turn's end.
            session.pendingQuestion = nil
            session.waitingMessage = nil
            if awaitsReply {
                session.state = .waiting
                session.turnStartedAt = nil
                session.needsAcknowledgement = true
            } else if liveSubagentCount > 0 {
                session.state = .running
            } else {
                session.state = .ended
                session.turnStartedAt = nil
                session.needsAcknowledgement = true
            }
        case let .waitingForUser(message):
            // Root cause B (#31): a genuine block moves the Session to waiting
            // from any live state, but never resurrects a turn that already
            // ended — a real permission/question never follows a finished turn,
            // so a stray notification must not turn a "terminé" back into "?".
            if session.state != .ended {
                session.state = .waiting
                session.needsAcknowledgement = true
                // The extracted AskUserQuestion (issue #26) — or nil for a
                // permission/free-text block — rides the event and is attached
                // only when we actually enter waiting; showing buttons never
                // clears the Liseré. A stray notification on an ended turn
                // attaches nothing.
                session.pendingQuestion = event.question
                // A buttonless block (permission prompt, or an unextractable
                // question — US10) keeps the Notification's human-readable ask
                // so the card can still say WHAT is waiting (issue #29). When
                // buttons ARE shown the question label is what the card reads,
                // so the generic message would be redundant → dropped.
                session.waitingMessage = event.question == nil ? message : nil
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

    /// Acknowledges every pending Session at once. Since ADR-0007 (issue #53)
    /// no production path clears the Liseré wholesale — revealing or hovering the
    /// Island acknowledges nothing (looking ≠ treating). Kept as a bulk helper.
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

    // MARK: - Answer from the Island (issue #27, US11)

    /// Optimistic feedback after the user answered a waiting Session from the
    /// Island by injection (issue #27): the Session flips back to `.running`
    /// immediately, its now-answered ``Session/pendingQuestion`` is cleared, and
    /// its Liseré goes out — through the **existing** per-Session Acknowledgement
    /// (`needsAcknowledgement`, the very field click-to-focus clears): answering
    /// *is* acting on the Session (ADR-0007). The elapsed clock restarts on the
    /// resumed turn.
    ///
    /// This never invents a terminal state: the real confirmation still arrives
    /// through the hooks (a fresh `promptSubmitted`/`toolStarted` overwrites this
    /// optimistic `.running`), so the state is never doubled. A no-op unless the
    /// Session is genuinely `.waiting`, so a stale or late tap can never
    /// resurrect an ended or already-running Session (US7).
    public func resumeAfterAnswer(sessionID: String) {
        guard let index = sessions.firstIndex(where: { $0.id == sessionID }),
            sessions[index].state == .waiting
        else { return }
        let timestamp = now()
        sessions[index].state = .running
        sessions[index].pendingQuestion = nil
        sessions[index].waitingMessage = nil
        sessions[index].needsAcknowledgement = false
        sessions[index].turnStartedAt = timestamp
        sessions[index].lastActivityAt = timestamp
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
