import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Answering a blocked Session from the Island (issue #27): tapping an option
/// button attempts a *safe-targeted* keystroke injection, and on any doubt
/// degrades to Click-to-focus — never a keystroke in the wrong terminal. The
/// real injection is a HITL FP; here the injection is a seam, so these tests
/// pin the controller's decision and the optimistic US11 feedback.
@MainActor
struct AnswerFromIslandTests {
    /// A waiting Session with an extractable question, hosted by ghostty.
    private func waitingStore() -> SessionStore {
        let store = SessionStore(sweepInterval: nil)
        let question = PendingQuestion(prompt: "Postgres or SQLite?", options: [
            .init(label: "Postgres"), .init(label: "SQLite")])
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            cwd: "/tmp/demo", terminal: "ghostty", agent: "claude-code", question: question))
        return store
    }

    @Test("Certain target: the option is injected and the Session resumes 'en cours' (US11)")
    func certainTargetInjectsAndResumes() {
        let store = waitingStore()
        var injectCalls: [(String?, Int)] = []
        var focused: [String?] = []
        let controller = IslandController(
            store: store,
            focusTerminal: { focused.append($0) },
            injectAnswer: { cwd, index in injectCalls.append((cwd, index)); return true })

        controller.optionSelected(sessionID: "s", optionIndex: 1)

        // The injector was asked to target this Session's cwd with option #2.
        #expect(injectCalls.map(\.0) == ["/tmp/demo"])
        #expect(injectCalls.map(\.1) == [1])
        // Optimistic feedback: back to 'en cours', question gone, Liseré out.
        let session = store.sessions[0]
        #expect(session.state == .running)
        #expect(session.pendingQuestion == nil)
        #expect(session.needsAcknowledgement == false)
        // A successful injection never also degrades to focus.
        #expect(focused.isEmpty)
    }

    @Test("Uncertain target: nothing is resumed, the click degrades to focus (US4/US5)")
    func uncertainTargetDegradesToFocus() {
        let store = waitingStore()
        var focused: [String?] = []
        let controller = IslandController(
            store: store,
            focusTerminal: { focused.append($0) },
            injectAnswer: { _, _ in false }) // uncertain / no permission

        controller.optionSelected(sessionID: "s", optionIndex: 0)

        // Degraded to Click-to-focus, exactly like tapping the card.
        #expect(focused == ["ghostty"])
        // The Session stays waiting on its question — nothing was answered — but
        // the Liseré is acknowledged (acting on the Session, #10).
        let session = store.sessions[0]
        #expect(session.state == .waiting)
        #expect(session.pendingQuestion != nil)
        #expect(session.needsAcknowledgement == false)
    }

    @Test("No injection is even attempted on a Session that is not waiting")
    func neverInjectsOnNonWaitingSession() {
        let store = SessionStore(sweepInterval: nil)
        store.apply(AgentEvent(
            sessionID: "run", kind: .promptSubmitted(prompt: "go"),
            cwd: "/tmp/demo", terminal: "ghostty", agent: "claude-code"))
        var injectCalls = 0
        var focused: [String?] = []
        let controller = IslandController(
            store: store,
            focusTerminal: { focused.append($0) },
            injectAnswer: { _, _ in injectCalls += 1; return true })

        controller.optionSelected(sessionID: "run", optionIndex: 0)

        // A stale tap on a Session that already left waiting never injects; it
        // degrades to focus.
        #expect(injectCalls == 0)
        #expect(focused == ["ghostty"])
        #expect(store.sessions[0].state == .running)
    }

    @Test("US7 invariant: without a click, nothing injects and the Session stays 'attend'")
    func noClickNoAutoDecision() {
        let store = waitingStore()
        var injectCalls = 0
        _ = IslandController(
            store: store,
            focusTerminal: { _ in },
            injectAnswer: { _, _ in injectCalls += 1; return true })

        // Drive more store activity (another Session appears): the controller
        // reacts, but there is no timer and no default answer — nothing injects.
        store.apply(AgentEvent(
            sessionID: "other", kind: .promptSubmitted(prompt: "x"),
            terminal: "ghostty", agent: "claude-code"))

        #expect(injectCalls == 0)
        let waiting = store.sessions.first { $0.id == "s" }
        #expect(waiting?.state == .waiting)
        #expect(waiting?.needsAcknowledgement == true) // Liseré still on
        #expect(waiting?.pendingQuestion != nil)
    }
}
