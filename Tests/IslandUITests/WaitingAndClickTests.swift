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
            sessionID: "done", kind: .turnEnded,
            terminal: "ghostty", agent: "claude-code"
        ))
        var focused: [String?] = []
        let controller = IslandController(store: store, focusTerminal: { focused.append($0) })

        controller.cardActivated(sessionID: "blocked")

        #expect(focused == ["ghostty"])
        #expect(store.sessions.first(where: { $0.id == "blocked" })?.needsAcknowledgement == false)
        #expect(store.sessions.first(where: { $0.id == "done" })?.needsAcknowledgement == true)
    }

    @Test("Hovering the Island acknowledges every pending Session")
    func hoverAcknowledgesEverySession() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "blocked", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(store: store)

        controller.hoverDidChange(true)

        #expect(store.sessions[0].needsAcknowledgement == false)
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
}
