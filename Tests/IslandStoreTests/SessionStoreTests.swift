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

        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0))
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

    @Test("The question tool's PreToolUse stashes the question; entering waiting promotes it (#77)")
    func questionStashedThenPromotedOnWaiting() {
        // The real captured sequence (docs/spikes/77-capture-pretooluse-
        // askuserquestion.md): PreToolUse(AskUserQuestion) carries the parsed
        // question, THEN the blocking Notification (which carries no options)
        // puts the Session in waiting.
        let store = SessionStore()
        let question = PendingQuestion(
            prompt: "Which sprite direction?",
            options: [.init(label: "Bots"), .init(label: "Blobs")])
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"), agent: "claude-code"))
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .toolStarted(tool: "AskUserQuestion"),
            agent: "claude-code", question: question))

        // Stashed, not displayed: buttons are visible IFF the Session waits.
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].pendingQuestion == nil)

        store.apply(AgentEvent(
            sessionID: "abc123",
            kind: .waitingForUser(message: "Claude needs your permission"),
            agent: "claude-code"))

        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].pendingQuestion == question)
        // Buttons shown → the generic message would be redundant (#29 mirror).
        #expect(store.sessions[0].waitingMessage == nil)
        // Carrying the question (buttons) must not pre-acknowledge the Liseré.
        #expect(store.sessions[0].needsAcknowledgement)
    }

    @Test("The question tool's PostToolUse resolves the question: stash and buttons cleared (#77)")
    func questionToolFinishedClearsStashAndQuestion() {
        // Answered in the terminal: the PostToolUse of the SAME tool arrives
        // while the Session still waits (the next state change comes later).
        // The now-answered question must not keep showing buttons.
        let store = SessionStore()
        let question = PendingQuestion(prompt: "Q?", options: [.init(label: "A"), .init(label: "B")])
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"), agent: "claude-code"))
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .toolStarted(tool: "AskUserQuestion"),
            agent: "claude-code", question: question))
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .waitingForUser(message: nil), agent: "claude-code"))
        #expect(store.sessions[0].pendingQuestion == question)

        store.apply(AgentEvent(
            sessionID: "abc123", kind: .toolFinished(tool: "AskUserQuestion"), agent: "claude-code"))

        #expect(store.sessions[0].pendingQuestion == nil)
        #expect(store.sessions[0].questionStash == nil)
    }

    @Test("Another tool's PostToolUse never resolves a stashed question (#77)")
    func otherToolFinishedKeepsStash() {
        // A parallel tool call finishing between the question's PreToolUse and
        // the blocking Notification must not eat the question.
        let store = SessionStore()
        let question = PendingQuestion(prompt: "Q?", options: [.init(label: "A"), .init(label: "B")])
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"), agent: "claude-code"))
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .toolStarted(tool: "AskUserQuestion"),
            agent: "claude-code", question: question))
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .toolFinished(tool: "Bash"), agent: "claude-code"))
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .waitingForUser(message: nil), agent: "claude-code"))

        #expect(store.sessions[0].pendingQuestion == question)
    }

    @Test("The stash follows pendingQuestion's lifecycle: prompt, turn end and Island answer clear it (#77)")
    func stashClearedWhereverQuestionIs() {
        let store = SessionStore()
        let question = PendingQuestion(prompt: "Q?", options: [.init(label: "A")])
        func stashQuestion() {
            store.apply(AgentEvent(
                sessionID: "abc123", kind: .toolStarted(tool: "AskUserQuestion"),
                agent: "claude-code", question: question))
            #expect(store.sessions[0].questionStash != nil)
        }

        // A fresh prompt starts a fresh turn: no stale stash may cross it.
        stashQuestion()
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "next"), agent: "claude-code"))
        #expect(store.sessions[0].questionStash == nil)

        // A finished turn carries no live question either (#26 mirror).
        stashQuestion()
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0),
            agent: "claude-code"))
        #expect(store.sessions[0].questionStash == nil)

        // Answering from the Island (#27) resolves the question: the stash must
        // not survive to be re-promoted by a stray notification.
        stashQuestion()
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .waitingForUser(message: nil), agent: "claude-code"))
        store.resumeAfterAnswer(sessionID: "abc123")
        #expect(store.sessions[0].questionStash == nil)
        #expect(store.sessions[0].pendingQuestion == nil)
    }

    @Test("A waiting event with no question (permission) leaves the Session buttonless")
    func waitingWithoutQuestionHasNoButtons() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "abc123",
            kind: .waitingForUser(message: "Claude needs your permission to use Bash"),
            agent: "claude-code"
        ))

        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].pendingQuestion == nil)
    }

    @Test("Entering waiting clears any running tool — a waiting Session has no tool in flight (#70)")
    func waitingClearsCurrentTool() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "go"), agent: "claude-code"))
        // A PreToolUse (e.g. AskUserQuestion) sets currentTool right before the
        // block's Notification arrives — the real #70 sequence.
        store.apply(AgentEvent(sessionID: "abc123", kind: .toolStarted(tool: "AskUserQuestion"), agent: "claude-code"))
        #expect(store.sessions[0].currentTool == "AskUserQuestion")

        store.apply(AgentEvent(
            sessionID: "abc123", kind: .waitingForUser(message: "May I?"), agent: "claude-code"))

        // A waiting Session is not running a tool: the stale "tool: …" label
        // must not linger above the question/message on the card (#70).
        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].currentTool == nil)
    }

    @Test("A buttonless permission wait surfaces the Notification message so the card says what blocks (#29)")
    func waitingWithoutQuestionSurfacesMessage() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"), agent: "claude-code"))

        store.apply(AgentEvent(
            sessionID: "abc123",
            kind: .waitingForUser(message: "Claude needs your permission to use Bash"),
            agent: "claude-code"
        ))

        // An escalated permission prompt carries no extractable options (#29,
        // spike #25): the human-readable ask rides the block so the buttonless
        // card still shows WHAT is waiting — display only, no button, no auto
        // decision (US7). The click keeps degrading to Click-to-focus.
        #expect(store.sessions[0].pendingQuestion == nil)
        #expect(store.sessions[0].waitingMessage == "Claude needs your permission to use Bash")
    }

    @Test("Showing buttons drops the generic message (no redundant text under the question, #29)")
    func waitingWithQuestionDropsMessage() {
        let store = SessionStore()
        let question = PendingQuestion(prompt: "Which?", options: [.init(label: "A"), .init(label: "B")])
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .toolStarted(tool: "AskUserQuestion"),
            agent: "claude-code", question: question))
        store.apply(AgentEvent(
            sessionID: "abc123",
            kind: .waitingForUser(message: "Claude is asking a question"),
            agent: "claude-code"))

        #expect(store.sessions[0].pendingQuestion == question)
        #expect(store.sessions[0].waitingMessage == nil)
    }

    @Test("A real permission block (gated tool's PreToolUse, no question) stays buttonless with its ask (#29/#77)")
    func permissionSequenceKeepsButtonlessMessage() {
        // The real escalated-permission sequence: the gated tool's PreToolUse
        // (no question in its payload) then the blocking Notification. No stash
        // → no promotion → no buttons, the human ask surfaces (#29 unchanged).
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Go"), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "abc123", kind: .toolStarted(tool: "Bash"), agent: "claude-code"))
        store.apply(AgentEvent(
            sessionID: "abc123",
            kind: .waitingForUser(message: "Claude needs your permission to use Bash"),
            agent: "claude-code"))

        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].pendingQuestion == nil)
        #expect(store.sessions[0].waitingMessage == "Claude needs your permission to use Bash")
    }

    @Test("A buttonless wait's message never lingers past waiting (#29)")
    func waitingMessageClearedOnResume() {
        let store = SessionStore()
        func enterPermissionWait() {
            store.apply(AgentEvent(
                sessionID: "abc123",
                kind: .waitingForUser(message: "Claude needs your permission to use Bash"),
                agent: "claude-code"))
            #expect(store.sessions[0].waitingMessage != nil)
        }

        // A new prompt, a resumed tool, or a finished turn all leave waiting: the
        // stale ask must not linger on the card (same lifecycle as pendingQuestion).
        enterPermissionWait()
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "next"), agent: "claude-code"))
        #expect(store.sessions[0].waitingMessage == nil)

        enterPermissionWait()
        store.apply(AgentEvent(sessionID: "abc123", kind: .toolStarted(tool: "Bash"), agent: "claude-code"))
        #expect(store.sessions[0].waitingMessage == nil)

        enterPermissionWait()
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0),
            agent: "claude-code"))
        #expect(store.sessions[0].waitingMessage == nil)
    }

    @Test("Answering clears the pending question so an old one is never re-shown")
    func answeringClearsPendingQuestion() {
        let store = SessionStore()
        let question = PendingQuestion(prompt: "Q?", options: [.init(label: "A")])
        func enterQuestionWait() {
            // The real sequence (#77): the question tool's PreToolUse stashes,
            // the blocking Notification promotes.
            store.apply(AgentEvent(
                sessionID: "abc123", kind: .toolStarted(tool: "AskUserQuestion"),
                agent: "claude-code", question: question))
            store.apply(AgentEvent(
                sessionID: "abc123", kind: .waitingForUser(message: nil), agent: "claude-code"))
            #expect(store.sessions[0].pendingQuestion != nil)
        }

        // A new prompt, a resumed tool, or a finished turn all leave waiting:
        // the stale question must not linger on the card.
        enterQuestionWait()
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "next"), agent: "claude-code"))
        #expect(store.sessions[0].pendingQuestion == nil)

        enterQuestionWait()
        store.apply(AgentEvent(sessionID: "abc123", kind: .toolStarted(tool: "Bash"), agent: "claude-code"))
        #expect(store.sessions[0].pendingQuestion == nil)

        enterQuestionWait()
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0),
            agent: "claude-code"))
        #expect(store.sessions[0].pendingQuestion == nil)
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
        store.apply(AgentEvent(sessionID: "done1", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0), agent: "claude-code"))
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
        store.apply(AgentEvent(sessionID: "done1", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "wait1", kind: .waitingForUser(message: nil), agent: "claude-code"))

        store.acknowledge(sessionID: "wait1")

        #expect(store.sessions.first(where: { $0.id == "wait1" })?.needsAcknowledgement == false)
        #expect(store.sessions.first(where: { $0.id == "done1" })?.needsAcknowledgement == true)
    }

    @Test("Focusing a terminal acknowledges the Sessions it hosts")
    func terminalFocusAcknowledgesItsSessions() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "ghosttySession", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0),
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
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0), agent: "claude-code", summary: summary))
        #expect(store.sessions.first?.lastSummary == summary)

        // A turn without a readable transcript falls back to no summary…
        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Again"), agent: "claude-code"))
        // …and the stale summary never survives into the new turn.
        #expect(store.sessions.first?.lastSummary == nil)
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0), agent: "claude-code"))
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

    // MARK: - Subagent gate via background_tasks (issues #31/#48, ADR-0008 amended)

    @Test("A constat with a live Sous-agent stays running, not ended — the gate (#48)")
    func constatWithLiveSubagentStaysRunning() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, cwd: "/tmp/demo", agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Explore the repo"))
        // The main turn ends on a constat while a Sous-agent still runs: the
        // Stop's background_tasks reports 1, read straight from the payload —
        // race-free, no need to wait for the subagent's own hooks.
        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 1))
        #expect(store.sessions[0].state == .running) // never "terminée" (#48)
        #expect(store.sessions[0].needsAcknowledgement == false)
        #expect(store.sessions[0].activeBackgroundTaskCount == 1)
    }

    @Test("The next Stop reporting zero live Sous-agents ends the turn, green (#48)")
    func laterStopWithZeroSubagentsEndsTurn() {
        let store = SessionStore()
        let summary = TurnSummary(text: "Explored.")
        func apply(_ kind: AgentEventKind, summary: TurnSummary? = nil) {
            store.apply(AgentEvent(
                sessionID: "abc123", kind: kind, cwd: "/tmp/demo",
                agent: "claude-code", summary: summary))
        }

        apply(.promptSubmitted(prompt: "Explore"))
        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 1)) // gated → running
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].needsAcknowledgement == false)

        // The Sous-agent finished ⇒ a fresh main turn ⇒ a fresh Stop whose
        // background_tasks is now empty: only now is the turn truly done.
        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0), summary: summary)
        #expect(store.sessions[0].state == .ended)
        #expect(store.sessions[0].needsAcknowledgement)
        #expect(store.sessions[0].lastSummary == summary)
        #expect(store.sessions[0].activeBackgroundTaskCount == 0)
    }

    @Test("Several concurrent Sous-agents: running until a Stop reports zero (#48)")
    func staysRunningUntilTheLastSubagentIsGone() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Go"))
        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 3)) // 3 live → running
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].activeBackgroundTaskCount == 3)

        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 1)) // some finished
        #expect(store.sessions[0].state == .running) // one still running
        #expect(store.sessions[0].activeBackgroundTaskCount == 1)

        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0)) // last one gone
        #expect(store.sessions[0].state == .ended)
    }

    @Test("A blocking notification never resurrects a turn that already ended (root cause B)")
    func waitingNeverResurrectsEndedTurn() {
        let store = SessionStore()
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0), agent: "claude-code"))
        #expect(store.sessions[0].state == .ended)

        // A stray notification reaching the store must not turn "terminé" into "?".
        store.apply(AgentEvent(
            sessionID: "abc123", kind: .waitingForUser(message: nil), agent: "claude-code"))

        #expect(store.sessions[0].state == .ended)
    }

    @Test("A real block waits from running, even with a Sous-agent in flight")
    func realBlockWaitsFromRunning() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code"))
        }

        apply(.promptSubmitted(prompt: "Go"))
        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 1)) // gated → running
        apply(.waitingForUser(message: "May I?")) // a genuine permission block

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

        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0))
        #expect(store.sessions[0].state == .ended) // the turn end clears the "?"
    }

    // MARK: - A turn ending on a question is "attend", not "terminé" (issue #39)

    @Test("A turn ending on a question waits (orange), not ends (green)")
    func turnEndingOnQuestionWaits() {
        let store = SessionStore()
        let question = TurnSummary(text: "Which database should I target, Postgres or SQLite?")

        store.apply(AgentEvent(sessionID: "abc123", kind: .promptSubmitted(prompt: "Add persistence"), agent: "claude-code"))
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: true, liveBackgroundTaskCount: 0), agent: "claude-code", summary: question))

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
        store.apply(AgentEvent(sessionID: "abc123", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0), agent: "claude-code"))

        #expect(store.sessions[0].state == .ended)
        #expect(store.sessions[0].needsAcknowledgement)
    }

    @Test("A question with a live Sous-agent waits IMMEDIATELY — the question wins (Q5, #48)")
    func questionWithLiveSubagentWaitsImmediately() {
        let store = SessionStore()
        let question = TurnSummary(text: "Ready to merge — proceed?")
        func apply(_ kind: AgentEventKind, summary: TurnSummary? = nil) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code", summary: summary))
        }

        apply(.promptSubmitted(prompt: "Prepare the merge"))
        // The main turn ends on a question while a Sous-agent still runs: the
        // question wins immediately (orange), the gate only ever holds back the
        // green of a constat (Q5 corrects the old deferred behavior, #48).
        apply(.turnEnded(awaitsReply: true, liveBackgroundTaskCount: 1), summary: question)
        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].needsAcknowledgement)
        #expect(store.sessions[0].turnStartedAt == nil)
        #expect(store.sessions[0].lastSummary == question)
    }

    @Test("Answering a final question starts a fresh turn that can end green (no stale orange)")
    func answeringAQuestionResetsTheChoice() {
        let store = SessionStore()
        func apply(_ kind: AgentEventKind, summary: TurnSummary? = nil) {
            store.apply(AgentEvent(sessionID: "abc123", kind: kind, agent: "claude-code", summary: summary))
        }

        apply(.promptSubmitted(prompt: "Add persistence"))
        apply(.turnEnded(awaitsReply: true, liveBackgroundTaskCount: 0), summary: TurnSummary(text: "Postgres or SQLite?"))
        #expect(store.sessions[0].state == .waiting)

        // The user answers: a fresh turn begins and the previous question is stale.
        apply(.promptSubmitted(prompt: "Postgres"))
        #expect(store.sessions[0].state == .running)
        #expect(store.sessions[0].lastSummary == nil)

        // This turn ends on a constat: green, not a leftover orange.
        apply(.turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0))
        #expect(store.sessions[0].state == .ended)
    }

    // MARK: - Answer from the Island (issue #27, US11)

    @Test("Answering from the Island resumes a waiting Session to 'working' optimistically")
    func resumeAfterAnswerFlipsWaitingToRunning() {
        var currentDate = Date(timeIntervalSince1970: 1_000_000)
        let store = SessionStore(now: { currentDate }, sweepInterval: nil)
        let question = PendingQuestion(prompt: "Postgres or SQLite?", options: [
            .init(label: "Postgres"), .init(label: "SQLite")])
        store.apply(AgentEvent(
            sessionID: "s", kind: .toolStarted(tool: "AskUserQuestion"),
            cwd: "/tmp/demo", terminal: "ghostty", agent: "claude-code", question: question))
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            cwd: "/tmp/demo", terminal: "ghostty", agent: "claude-code"))
        #expect(store.sessions[0].state == .waiting)
        #expect(store.sessions[0].needsAcknowledgement)
        #expect(store.sessions[0].pendingQuestion != nil)

        currentDate = Date(timeIntervalSince1970: 1_000_050)
        store.resumeAfterAnswer(sessionID: "s")

        let session = store.sessions[0]
        // Optimistic US11 feedback: back to 'en cours', the answered question
        // gone, and the Liseré out via the existing Acknowledgement field.
        #expect(session.state == .running)
        #expect(session.pendingQuestion == nil)
        #expect(session.needsAcknowledgement == false)
        // The resumed turn starts its elapsed clock now.
        #expect(session.turnStartedAt == Date(timeIntervalSince1970: 1_000_050))
    }

    @Test("Answering never resurrects a Session that is not waiting (no double state)")
    func resumeAfterAnswerNoOpUnlessWaiting() {
        let store = SessionStore(sweepInterval: nil)
        // An ended Session: a stray/late tap must not turn it back to 'en cours'.
        store.apply(AgentEvent(
            sessionID: "done", kind: .turnEnded(awaitsReply: false, liveBackgroundTaskCount: 0),
            terminal: "ghostty", agent: "claude-code"))
        #expect(store.sessions[0].state == .ended)

        store.resumeAfterAnswer(sessionID: "done")
        #expect(store.sessions[0].state == .ended)
        #expect(store.sessions[0].needsAcknowledgement) // untouched

        // An unknown Session id is a silent no-op.
        store.resumeAfterAnswer(sessionID: "ghost")
        #expect(store.sessions.count == 1)
    }
}
