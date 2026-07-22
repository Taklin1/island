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

    @Test("A waiting card carries the question label and its options in order")
    func waitingCardCarriesQuestion() {
        let question = PendingQuestion(
            prompt: "Which sprite direction?",
            options: [.init(label: "Bots"), .init(label: "Blobs"), .init(label: "None")])
        let card = SessionCard(
            session: Session(
                id: "x", state: .waiting, agent: "claude-code", pendingQuestion: question),
            home: "/Users/loic")

        #expect(card.question?.prompt == "Which sprite direction?")
        // Order preserved: the index is the 1/2/3 key mapping shown on buttons.
        #expect(card.question?.options.map(\.label) == ["Bots", "Blobs", "None"])
    }

    @Test("Only a waiting card shows question buttons; a lingering one never leaks")
    func onlyWaitingCardShowsQuestion() {
        // Buttons make sense only while waiting; a stale question on a resumed
        // Session must not render.
        let question = PendingQuestion(prompt: "Q?", options: [.init(label: "A")])
        let running = SessionCard(
            session: Session(
                id: "x", state: .running, agent: "claude-code", pendingQuestion: question),
            home: "/Users/loic")
        #expect(running.question == nil)

        // A waiting Session with no extractable question shows no buttons (US10).
        let permission = SessionCard(
            session: Session(id: "y", state: .waiting, agent: "claude-code"),
            home: "/Users/loic")
        #expect(permission.question == nil)
    }

    @Test("A buttonless waiting card surfaces the permission ask; buttons or non-waiting drop it (#29)")
    func waitingCardSurfacesPermissionMessage() {
        // An escalated permission block: no extractable options, so the card
        // shows the Notification's ask instead — WHAT is waiting, with no
        // buttons (display only, click still degrades to focus).
        let permission = SessionCard(
            session: Session(
                id: "p", state: .waiting, agent: "claude-code",
                waitingMessage: "Claude needs your permission to use Bash"),
            home: "/Users/loic")
        #expect(permission.question == nil)
        #expect(permission.waitingMessage == "Claude needs your permission to use Bash")

        // When buttons ARE shown, the question label is the card's text; the
        // generic message would be redundant, so the card never doubles it.
        let question = PendingQuestion(prompt: "Which?", options: [.init(label: "A")])
        let withButtons = SessionCard(
            session: Session(
                id: "q", state: .waiting, agent: "claude-code",
                pendingQuestion: question, waitingMessage: "ignored"),
            home: "/Users/loic")
        #expect(withButtons.waitingMessage == nil)

        // A stale message on a resumed Session never leaks onto the card.
        let running = SessionCard(
            session: Session(
                id: "r", state: .running, agent: "claude-code", waitingMessage: "stale"),
            home: "/Users/loic")
        #expect(running.waitingMessage == nil)
    }

    @Test("The sessions trace surfaces a waiting Session's pending question and option count")
    func sessionsTraceShowsPendingQuestion() {
        let question = PendingQuestion(
            prompt: "Q?", options: [.init(label: "A"), .init(label: "B"), .init(label: "C")])
        let withButtons = Session(
            id: "w", state: .waiting, cwd: "/tmp/demo", agent: "claude-code",
            pendingQuestion: question)
        let permission = Session(id: "p", state: .waiting, cwd: "/tmp/demo", agent: "claude-code")

        let trace = IslandController.sessionsTrace(for: [withButtons, permission])
        // State first: the FP asserts extraction from stdout; pixels stay visual.
        #expect(trace.contains("demo[w]=waiting+question(3)"))
        #expect(trace.contains("demo[p]=waiting"))
        #expect(!trace.contains("p]=waiting+question"))
    }

    @Test("The sessions trace marks a buttonless wait that surfaced its ask (#29 FP hook)")
    func sessionsTraceShowsSurfacedWaitingMessage() {
        let permission = Session(
            id: "p", state: .waiting, cwd: "/tmp/demo", agent: "claude-code",
            waitingMessage: "Claude needs your permission to use Bash")
        let bare = Session(id: "b", state: .waiting, cwd: "/tmp/demo", agent: "claude-code")

        let trace = IslandController.sessionsTrace(for: [permission, bare])
        // The FP asserts the escalated permission surfaced (state-first, #29);
        // a bare wait with no message carries no marker.
        #expect(trace.contains("demo[p]=waiting+msg"))
        #expect(trace.contains("demo[b]=waiting"))
        #expect(!trace.contains("b]=waiting+msg"))
    }

    @Test("Clicking a card focuses the terminal and acknowledges that Session only")
    func cardClickFocusesAndAcknowledges() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "blocked", kind: .waitingForUser(message: nil),
            cwd: "/tmp/demo", terminal: "ghostty", agent: "claude-code"
        ))
        store.apply(AgentEvent(
            sessionID: "done", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0),
            terminal: "ghostty", agent: "claude-code"
        ))
        var focused: [(terminal: String?, cwd: String?)] = []
        let controller = IslandController(
            store: store, focusTerminal: { focused.append(($0, $1)) })

        controller.cardActivated(sessionID: "blocked")

        // The Session's cwd travels with the focus (#36): the focuser needs it
        // to target the exact Ghostty window when it is a certain target.
        #expect(focused.count == 1)
        #expect(focused.first?.terminal == "ghostty")
        #expect(focused.first?.cwd == "/tmp/demo")
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
