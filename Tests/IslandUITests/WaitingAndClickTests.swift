import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Waiting state on the cards/compact bar (issue #8) and click-to-focus
/// behavior (issue #10). Pure logic + controller behavior; pixels stay visual.
@MainActor
struct WaitingAndClickTests {
    @Test("A waiting Session shows the French 'attend' state and its glyph")
    func waitingSessionPresentation() {
        let card = SessionCard(
            session: Session(id: "x", state: .waiting, agent: "claude-code"),
            home: "/Users/loic"
        )

        #expect(card.stateLabel == "attend")
        #expect(card.animation == .question)
    }

    @Test("The compact bar tone mirrors the Sessions: orange when one waits, over green")
    func compactToneReflectsSessions() {
        let waiting = Session(id: "w", state: .waiting, agent: "claude-code")
        let ended = Session(id: "e", state: .ended, agent: "claude-code")
        let running = Session(id: "r", state: .running, agent: "claude-code")

        #expect(IslandController.compactTone(for: [running]) == .neutral)
        #expect(IslandController.compactTone(for: [ended, running]) == .finished)
        // Orange (waiting) always wins over green (finished).
        #expect(IslandController.compactTone(for: [ended, waiting]) == .waiting)
        #expect(IslandController.compactTone(for: []) == .neutral)
    }

    @Test("Clicking a card focuses the terminal and acknowledges that Session only")
    func cardClickFocusesAndAcknowledges() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "blocked", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        store.apply(AgentEvent(
            sessionID: "done", kind: .turnEnded(awaitsReply: false, liveSubagentCount: 0),
            terminal: "ghostty", agent: "claude-code"
        ))
        var focused: [String?] = []
        let controller = IslandController(store: store, focusTerminal: { focused.append($0) })

        controller.cardActivated(sessionID: "blocked")

        #expect(focused == ["ghostty"])
        #expect(store.sessions.first(where: { $0.id == "blocked" })?.needsAcknowledgement == false)
        #expect(store.sessions.first(where: { $0.id == "done" })?.needsAcknowledgement == true)
    }

    @Test("Hovering the revealed Island acknowledges no Session (regarder ≠ traiter, #53)")
    func hoverAcknowledgesNoSession() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "blocked", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(store: store)

        controller.hoverDidChange(true)

        // Redefined Acknowledgement (ADR-0007): looking at the Island — revealing
        // or hovering it — no longer clears the Liseré. Only acting on a Session
        // (click-to-focus or terminal refocus) acknowledges it, one at a time.
        #expect(store.sessions[0].needsAcknowledgement == true)
    }

    @Test("The Peek announces a waiting Session differently from a finished one")
    func peekTextTellsWaitingFromFinished() {
        let waiting = Session(
            id: "w", state: .waiting, cwd: "/tmp/demo", agent: "claude-code")
        let ended = Session(
            id: "e", state: .ended, cwd: "/tmp/demo", agent: "claude-code")

        #expect(IslandController.peekText(for: waiting) == "demo ? attend une réponse")
        #expect(IslandController.peekText(for: ended) == "demo ✓ terminé")
    }

    @Test("The Peek of a question-wait announces the question (#39)")
    func peekTextOfQuestionWaitShowsTheQuestion() {
        let questionWait = Session(
            id: "q", state: .waiting, cwd: "/tmp/demo", agent: "claude-code",
            lastSummary: TurnSummary(text: "Should I target Postgres or SQLite?"))

        #expect(IslandController.peekText(for: questionWait)
            == "demo · attend : \"Should I target Postgres or SQLite?\"")
    }
}
