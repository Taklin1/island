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

        apply(.turnEnded)
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
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded, agent: "claude-code", summary: summary))
        #expect(store.sessions.first?.lastSummary == summary)

        // A turn without a readable transcript falls back to no summary…
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Again"), agent: "claude-code"))
        // …and the stale summary never survives into the new turn.
        #expect(store.sessions.first?.lastSummary == nil)
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded, agent: "claude-code"))
        #expect(store.sessions.first?.lastSummary == nil)
        #expect(store.sessions.first?.state == .ended)
    }
}
