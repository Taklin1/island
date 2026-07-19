import Foundation
import Testing
import IslandStore

@MainActor
struct SessionStoreTests {
    @Test("A sessionStarted event publishes an idle Session named after its project")
    func sessionStartedPublishesIdleSession() {
        let store = SessionStore()

        store.apply(AgentEvent(
            sessionID: "abc123",
            kind: .sessionStarted,
            cwd: "/Users/loic/Documents/island",
            agent: "claude-code"
        ))

        #expect(store.sessions.count == 1)
        let session = store.sessions[0]
        #expect(session.id == "abc123")
        #expect(session.state == .idle)
        #expect(session.projectName == "island")
    }

    @Test("A full turn: start → prompt → tool → tool done → turn ended")
    func fullTurnLifecycle() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, cwd: "/tmp/demo", agent: "claude-code"))
        }

        apply(.sessionStarted)
        #expect(store.sessions[0].state == .idle)

        apply(.promptSubmitted(prompt: "Fix the login bug"))
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].lastPrompt == "Fix the login bug")
        #expect(store.sessions[0].turnStartedAt != nil)

        apply(.toolStarted(tool: "Bash"))
        #expect(store.sessions[0].currentTool == "Bash")
        #expect(store.sessions[0].state == .running)

        apply(.toolFinished(tool: "Bash"))
        #expect(store.sessions[0].currentTool == nil)
        #expect(store.sessions[0].state == .running)

        apply(.turnEnded(awaitsReply: false))
        #expect(store.sessions[0].state == .ended)
        #expect(store.sessions[0].currentTool == nil)
        #expect(store.sessions[0].turnStartedAt == nil)
        #expect(store.sessions[0].lastPrompt == "Fix the login bug")
        #expect(store.sessions.count == 1)
    }

    @Test("A closed Session disappears from the Island")
    func sessionEndedRemovesSession() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .sessionStarted, agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "other", kind: .sessionStarted, agent: "claude-code"))

        store.apply(AgentEvent(sessionID: "abc123", kind: .sessionEnded, agent: "claude-code"))

        #expect(store.sessions.map(\.id) == ["other"])
    }

    @Test("SessionStart on a known Session (resume) upserts instead of duplicating")
    func resumeUpsertsWithoutDuplicate() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .sessionStarted, cwd: "/tmp/demo", agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"), agent: "claude-code"))

        // Resume (or SessionStart after auto-compact) on a session mid-turn.
        store.apply(AgentEvent(sessionID: "abc123", kind: .sessionStarted, cwd: "/tmp/demo", agent: "claude-code"))

        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].lastPrompt == "Go")
    }

    @Test("A tool event for an unknown Session creates it (Island launched mid-session)")
    func toolEventOnUnknownSessionCreatesIt() {
        let store = SessionStore()

        store.apply(AgentEvent(sessionID: "late1", kind: .toolStarted(tool: "Edit"), cwd: "/tmp/demo", agent: "claude-code"))

        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].currentTool == "Edit")
        #expect(store.sessions[0].turnStartedAt != nil)
    }

    @Test("An orphan Session (no SessionEnd) expires after the inactivity TTL")
    func orphanSessionExpiresAfterTTL() {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let store = SessionStore(now: { currentDate }, inactivityTTL: 60)

        store.apply(AgentEvent(sessionID: "orphan", kind: .promptSubmitted(prompt: "Hi"), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "alive", kind: .sessionStarted, agent: "claude-code"))

        // "alive" keeps receiving events; "orphan" goes silent.
        currentDate += 45
        store.apply(AgentEvent(sessionID: "alive", kind: .toolStarted(tool: "Bash"), agent: "claude-code"))
        currentDate += 45
        store.purgeExpiredSessions()

        #expect(store.sessions.map(\.id) == ["alive"])
    }

    // MARK: - Waiting state and Acknowledgement (issues #8 / #10)

    @Test("A waitingForUser event puts the Session in waiting, pending Acknowledgement")
    func waitingForUserAwaitsAcknowledgement() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"), agent: "claude-code"))

        store.apply(AgentEvent(
            sessionID: "abc123",
            kind: .waitingForUser(message: "Claude needs your permission to use Bash"),
            agent: "claude-code"
        ))

        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].needsAcknowledgement)
    }

    @Test("Answering (prompt or tool resuming) leaves waiting and clears the Acknowledgement flag")
    func answeringClearsWaitingAndAcknowledgement() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .waitingForUser(message: "May I?"), agent: "claude-code"))

        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "yes"), agent: "claude-code"))

        #expect(store.sessions[0].state == .running)
        #expect(!store.sessions[0].needsAcknowledgement)

        // Permission granted: the agent resumes straight into a tool call.
        store.apply(AgentEvent(sessionID: "abc123", kind: .waitingForUser(message: "May I?"), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "abc123", kind: .toolStarted(tool: "Bash"), agent: "claude-code"))

        #expect(store.sessions[0].state == .running)
        #expect(!store.sessions[0].needsAcknowledgement)
    }

    @Test("A finished turn awaits Acknowledgement; hovering the Island acknowledges every Session")
    func hoverAcknowledgesAllSessions() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "done1", kind: .turnEnded(awaitsReply: false), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "wait1", kind: .waitingForUser(message: nil), agent: "claude-code"))

        let allPending = store.sessions.allSatisfy { $0.needsAcknowledgement }
        #expect(allPending)

        store.acknowledgeAll()

        let nonePending = store.sessions.allSatisfy { !$0.needsAcknowledgement }
        #expect(nonePending)
        // Acknowledgement clears the Liseré, never the Session state itself.
        #expect(store.sessions.first(where: { $0.id == "done1" })?.state == .ended)
        #expect(store.sessions.first(where: { $0.id == "wait1" })?.state == .waiting)
    }

    @Test("Acknowledging one Session leaves the others pending")
    func acknowledgeSingleSession() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "done1", kind: .turnEnded(awaitsReply: false), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "wait1", kind: .waitingForUser(message: nil), agent: "claude-code"))

        store.acknowledge(sessionID: "wait1")

        #expect(store.sessions.first(where: { $0.id == "wait1" })?.needsAcknowledgement == false)
        #expect(store.sessions.first(where: { $0.id == "done1" })?.needsAcknowledgement == true)
    }

    @Test("Focusing a terminal acknowledges the Sessions it hosts")
    func terminalFocusAcknowledgesItsSessions() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "ghosttySession", kind: .turnEnded(awaitsReply: false),
            terminal: "ghostty", agent: "claude-code"
        ))
        store.apply(AgentEvent(
            sessionID: "otherTerminal", kind: .waitingForUser(message: nil),
            terminal: "iterm", agent: "claude-code"
        ))

        store.acknowledge(terminal: "ghostty")

        #expect(store.sessions.first(where: { $0.id == "ghosttySession" })?.needsAcknowledgement == false)
        #expect(store.sessions.first(where: { $0.id == "otherTerminal" })?.needsAcknowledgement == true)
        #expect(store.sessions.first(where: { $0.id == "ghosttySession" })?.terminal == "ghostty")
    }

    @Test("Any event refreshes the inactivity TTL of its Session")
    func activityRefreshesTTL() {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let store = SessionStore(now: { currentDate }, inactivityTTL: 60)

        store.apply(AgentEvent(sessionID: "busy", kind: .sessionStarted, agent: "claude-code"))
        for _ in 0..<5 {
            currentDate += 45
            store.apply(AgentEvent(sessionID: "busy", kind: .toolStarted(tool: "Bash"), agent: "claude-code"))
        }
        store.purgeExpiredSessions()

        #expect(store.sessions.map(\.id) == ["busy"])
    }

    @Test("A turnEnded event's summary is published on the Session, until the next prompt")
    func turnEndedPublishesSummary() {
        let store = SessionStore()
        let summary = TurnSummary(
            text: "Fixed the parser crash.",
            todosDone: 1,
            todosTotal: 3,
            filesModified: ["/tmp/demo/Parser.swift"],
            turnDuration: 200
        )

        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Fix it"), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false), agent: "claude-code", summary: summary))
        #expect(store.sessions.first?.lastSummary == summary)

        // A turn without a readable transcript falls back to no summary…
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Again"), agent: "claude-code"))
        // …and the stale summary never survives into the new turn.
        #expect(store.sessions.first?.lastSummary == nil)
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false), agent: "claude-code"))
        #expect(store.sessions.first?.lastSummary == nil)
        #expect(store.sessions.first?.state == .ended)
    }

    // MARK: - Session title (issue #32)

    @Test("An event carrying a title publishes it on the Session")
    func eventPublishesSessionTitle() {
        let store = SessionStore()

        store.apply(AgentEvent(
            sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"),
            cwd: "/Users/loic/Documents/island", agent: "claude-code",
            title: "Fix the parser crash"))

        #expect(store.sessions[0].title == "Fix the parser crash")
    }

    @Test("A later ai-title (rename) updates the Session title; a titleless event keeps the last one")
    func titleUpdatesOnRenameAndSurvivesTitlelessEvents() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind, title: String? = nil) {
            store.apply(AgentEvent(
                sessionID: "abc123", kind: kind, cwd: "/tmp/demo",
                agent: "claude-code", title: title))
        }

        apply(.promptSubmitted(prompt: "Go"), title: "Original title")
        #expect(store.sessions[0].title == "Original title")

        // A tool event without a readable title must not wipe the known one.
        apply(.toolStarted(tool: "Bash"))
        #expect(store.sessions[0].title == "Original title")

        // A rename shows up as a fresh title on a later event.
        apply(.toolFinished(tool: "Bash"), title: "Renamed by the user")
        #expect(store.sessions[0].title == "Renamed by the user")
    }

    @Test("setTitle updates a known Session out of band, and is a no-op otherwise (#32 hover refresh)")
    func setTitleUpdatesKnownSessionOnly() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s1", kind: .promptSubmitted(prompt: "Go"),
            cwd: "/tmp/demo", agent: "claude-code", title: "Old title"))
        #expect(store.sessions[0].title == "Old title")

        // The hover refresh found a fresher title in the transcript.
        store.setTitle("Renamed while idle", forSessionID: "s1")
        #expect(store.sessions[0].title == "Renamed while idle")

        // Unknown Session: no crash, no new Session.
        store.setTitle("whatever", forSessionID: "ghost")
        #expect(store.sessions.count == 1)
    }

    // MARK: - Subagents and real-time state fidelity (issue #31)

    @Test("A Stop while a subagent is still running keeps the Session running, not ended")
    func stopWithActiveSubagentStaysRunning() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, cwd: "/tmp/demo", agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Explore the repo"))
        apply(.subagentStarted)
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].activeSubagentCount == 1)

        // The main turn's Stop fires while the subagent is still working.
        apply(.turnEnded(awaitsReply: false))
        #expect(store.sessions[0].state == .running) // never "terminée" (#31)
        #expect(store.sessions[0].needsAcknowledgement == false)
    }

    @Test("The last SubagentStop, arriving AFTER the main Stop, finishes the turn")
    func lastSubagentStopAfterMainStopEndsTurn() {
        let store = SessionStore()
        let summary = TurnSummary(text: "Explored.")
        func apply(_ kind: AgentEventKind, summary: TurnSummary? = nil) {
            store.apply(AgentEvent(
                sessionID: "abc123", kind: kind, cwd: "/tmp/demo",
                agent: "claude-code", summary: summary))
        }

        apply(.promptSubmitted(prompt: "Explore"))
        apply(.subagentStarted)
        apply(.turnEnded(awaitsReply: false), summary: summary) // Stop arrives before the subagent stops
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].needsAcknowledgement == false)

        apply(.subagentStopped) // last subagent gone → only now ended
        #expect(store.sessions[0].state == .ended)
        #expect(store.sessions[0].needsAcknowledgement)
        #expect(store.sessions[0].lastSummary == summary)
        #expect(store.sessions[0].activeSubagentCount == 0)
    }

    @Test("Several subagents: ended only once the last one stops")
    func endedOnlyAfterEverySubagentStops() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Go"))
        apply(.subagentStarted)
        apply(.subagentStarted)
        apply(.turnEnded(awaitsReply: false))
        #expect(store.sessions[0].state == .running)

        apply(.subagentStopped)
        #expect(store.sessions[0].state == .running) // one still running
        apply(.subagentStopped)
        #expect(store.sessions[0].state == .ended) // last one gone
    }

    @Test("A subagent that finishes before the main Stop: the turn ends as usual")
    func subagentFinishingBeforeStopEndsNormally() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Go"))
        apply(.subagentStarted)
        apply(.subagentStopped) // subagent done before the main Stop
        #expect(store.sessions[0].state == .running) // main turn still going
        apply(.turnEnded(awaitsReply: false))
        #expect(store.sessions[0].state == .ended) // no subagent left → ended
    }

    @Test("Subagent events for an unknown Session create no Session")
    func subagentEventsNeverCreateASession() {
        let store = SessionStore()

        store.apply(AgentEvent(sessionID: "ghost", kind: .subagentStopped, agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "ghost", kind: .subagentStarted, agent: "claude-code"))

        #expect(store.sessions.isEmpty)
    }

    @Test("A blocking notification never resurrects a turn that already ended (root cause B)")
    func waitingNeverResurrectsEndedTurn() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false), agent: "claude-code"))
        #expect(store.sessions[0].state == .ended)

        // A stray notification reaching the store must not turn "terminé" into "?".
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .waitingForUser(message: nil), agent: "claude-code"))

        #expect(store.sessions[0].state == .ended)
    }

    @Test("A real block waits from running, even with a subagent in flight")
    func realBlockWaitsFromRunning() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Go"))
        apply(.subagentStarted)
        apply(.waitingForUser(message: "May I?"))

        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].needsAcknowledgement)
    }

    @Test("A finished turn clears a pending '?' (waiting → ended)")
    func turnEndClearsWaiting() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Go"))
        apply(.waitingForUser(message: "May I?"))
        #expect(store.sessions[0].state == .waiting)

        apply(.turnEnded(awaitsReply: false))
        #expect(store.sessions[0].state == .ended) // the turn end clears the "?"
    }

    @Test("A real block during subagent wrap-up survives the last SubagentStop")
    func blockDuringWrapUpSurvivesLastSubagentStop() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Go"))
        apply(.subagentStarted)
        apply(.turnEnded(awaitsReply: false)) // main Stop, subagent still running → running
        apply(.waitingForUser(message: "May I?")) // a genuine block appears
        #expect(store.sessions[0].state == .waiting)

        // The last subagent stops: finalization must NOT wipe the "?".
        apply(.subagentStopped)
        #expect(store.sessions[0].state == .waiting)
    }

    // MARK: - A turn ending on a question is "attend", not "terminé" (issue #39)

    @Test("A turn ending on a question waits (orange), not ends (green)")
    func turnEndingOnQuestionWaits() {
        let store = SessionStore()
        let question = TurnSummary(text: "Which database should I target, Postgres or SQLite?")

        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Add persistence"), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: true), agent: "claude-code", summary: question))

        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].needsAcknowledgement)
        #expect(store.sessions[0].turnStartedAt == nil)
        // The question is kept on the Session so the Peek can show it (#39 bonus).
        #expect(store.sessions[0].lastSummary == question)
    }

    @Test("A turn ending on a constat still ends (green)")
    func turnEndingOnConstatEnds() {
        let store = SessionStore()

        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Ship it"), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false), agent: "claude-code"))

        #expect(store.sessions[0].state == .ended)
        #expect(store.sessions[0].needsAcknowledgement)
    }

    @Test("A question with a subagent in flight stays running, then the last SubagentStop waits")
    func questionWithActiveSubagentDefersToWaiting() {
        let store = SessionStore()
        let question = TurnSummary(text: "Ready to merge — proceed?")
        func apply(_ kind: AgentEventKind, summary: TurnSummary? = nil) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code", summary: summary))
        }

        apply(.promptSubmitted(prompt: "Prepare the merge"))
        apply(.subagentStarted)
        // The main Stop ends on a question while the subagent is still working:
        // the gate (#31) keeps it running, never orange mid-work.
        apply(.turnEnded(awaitsReply: true), summary: question)
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].needsAcknowledgement == false)

        // The last subagent stops: the deferred completion inherits the choice
        // — question ⇒ waiting, not ended.
        apply(.subagentStopped)
        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].needsAcknowledgement)
        #expect(store.sessions[0].lastSummary == question)
    }

    @Test("A constat with a subagent in flight defers to ended, not waiting")
    func constatWithActiveSubagentDefersToEnded() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Explore"))
        apply(.subagentStarted)
        apply(.turnEnded(awaitsReply: false))
        #expect(store.sessions[0].state == .running)

        apply(.subagentStopped)
        #expect(store.sessions[0].state == .ended)
    }

    @Test("Answering a final question starts a fresh turn that can end green (no stale orange)")
    func answeringAQuestionResetsTheChoice() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind, summary: TurnSummary? = nil) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code", summary: summary))
        }

        apply(.promptSubmitted(prompt: "Add persistence"))
        apply(.turnEnded(awaitsReply: true), summary: TurnSummary(text: "Postgres or SQLite?"))
        #expect(store.sessions[0].state == .waiting)

        // The user answers: a fresh turn begins and the previous question is stale.
        apply(.promptSubmitted(prompt: "Postgres"))
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].lastSummary == nil)

        // This turn ends on a constat: green, not a leftover orange.
        apply(.turnEnded(awaitsReply: false))
        #expect(store.sessions[0].state == .ended)
    }
}
