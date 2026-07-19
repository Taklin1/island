import Foundation
import Testing
import IslandStore

@MainActor
struct SessionStoreTests {
    @Test("An 'ended' event publishes a terminated Session named after its project")
    func endedEventPublishesTerminatedSession() {
        let store = SessionStore()

        store.apply(AgentEvent(
            sessionID: "abc123",
            state: .ended,
            cwd: "/Users/loic/Documents/island",
            agent: "claude-code"
        ))

        #expect(store.sessions.count == 1)
        let session = store.sessions[0]
        #expect(session.id == "abc123")
        #expect(session.state == .ended)
        #expect(session.projectName == "island")
    }

    @Test("Events for the same session update it instead of duplicating it")
    func sameSessionIsUpdatedNotDuplicated() {
        let store = SessionStore()
        let active = AgentEvent(sessionID: "abc123", state: .active, cwd: "/tmp/demo", agent: "claude-code")
        let ended = AgentEvent(sessionID: "abc123", state: .ended, cwd: "/tmp/demo", agent: "claude-code")

        store.apply(active)
        store.apply(ended)

        #expect(store.sessions.count == 1)
        #expect(store.sessions[0].state == .ended)
    }
}
