import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Pure presentation logic of the Island (PRD #3, Testing Decisions): the
/// SwiftUI rendering is checked visually, but labels, glyphs and durations
/// are plain functions and are tested here.
@MainActor
struct SessionPresentationTests {
    // The compact bar itself is covered by SpriteTests (issue #11): one
    // Sprite per Session, its animation encoding the state.

    @Test("A Session card carries project, French state, prompt and tool")
    func sessionCardCarriesTheExpandedFields() {
        let session = Session(
            id: "abc123",
            state: .running,
            cwd: "/Users/loic/Documents/island",
            agent: "claude-code",
            lastPrompt: "Fix the login bug",
            currentTool: "Bash",
            turnStartedAt: Date(timeIntervalSince1970: 42)
        )

        let card = SessionCard(session: session, home: "/Users/loic")

        #expect(card.project == "island")
        #expect(card.location == "~/Documents/island")
        #expect(card.stateLabel == "en cours")
        #expect(card.lastPrompt == "Fix the login bug")
        #expect(card.currentTool == "Bash")
        #expect(card.turnStartedAt == Date(timeIntervalSince1970: 42))
    }

    // MARK: - Discreet background-task tally (issue #48, widened by #79, Q6)

    @Test("The card shows a discreet count of live background tasks, singular/plural")
    func cardShowsLiveBackgroundTaskTally() {
        func label(_ count: Int) -> String? {
            SessionCard(
                session: Session(
                    id: "x", state: .running, agent: "claude-code",
                    activeBackgroundTaskCount: count),
                home: "/Users/loic"
            ).backgroundTasksLabel
        }

        // Type-neutral wording (#79): the count mixes Sous-agents, workflows…
        #expect(label(0) == nil) // nothing to show
        #expect(label(1) == "1 tâche de fond en cours")
        #expect(label(3) == "3 tâches de fond en cours")
    }

    // MARK: - Session title header (issue #32)

    @Test("The card header shows the session title when there is one")
    func cardHeaderShowsTheSessionTitle() {
        let session = Session(
            id: "abc123", state: .running,
            cwd: "/Users/loic/Documents/island", title: "Fix the parser crash",
            agent: "claude-code")

        let card = SessionCard(session: session, home: "/Users/loic")

        // Title on top, project path underneath (the folder name alone was
        // redundant with the path).
        #expect(card.title == "Fix the parser crash")
        #expect(card.location == "~/Documents/island")
    }

    @Test("Without a title the card header falls back to the project folder name")
    func cardHeaderFallsBackToFolderName() {
        let session = Session(
            id: "abc123", state: .running,
            cwd: "/Users/loic/Documents/island", agent: "claude-code")

        let card = SessionCard(session: session, home: "/Users/loic")

        #expect(card.title == "island")
    }

    @Test("Two Sessions in the same project show distinct titles")
    func sameProjectDistinctTitles() {
        func card(_ title: String?) -> SessionCard {
            SessionCard(
                session: Session(
                    id: UUID().uuidString, state: .running,
                    cwd: "/Users/loic/Documents/island", title: title,
                    agent: "claude-code"),
                home: "/Users/loic")
        }

        let a = card("Fix the parser crash")
        let b = card("Ship the release")
        #expect(a.title != b.title)
        // …while the project path stays the same for both.
        #expect(a.location == b.location)
    }

    @Test("Session states map to French labels")
    func statesMapToFrenchLabels() {
        func card(_ state: SessionState) -> SessionCard {
            SessionCard(session: Session(id: "x", state: state, agent: "claude-code"), home: "/Users/loic")
        }

        #expect(card(.idle).stateLabel == "démarrée")
        #expect(card(.running).stateLabel == "en cours")
        #expect(card(.ended).stateLabel == "terminée")
    }

    @Test("Elapsed turn duration is rendered compactly")
    func durationIsRenderedCompactly() {
        #expect(SessionCard.durationText(seconds: 5) == "0:05")
        #expect(SessionCard.durationText(seconds: 65) == "1:05")
        #expect(SessionCard.durationText(seconds: 3_725) == "1:02:05")
    }

    @Test("The card carries the turn summary: detail text and one facts line")
    func cardCarriesTheSummary() {
        let session = Session(
            id: "abc123",
            state: .ended,
            cwd: "/Users/loic/Documents/island",
            agent: "claude-code",
            lastSummary: TurnSummary(
                text: "Fixed the parser crash.\n\n- added a regression test",
                todosDone: 1,
                todosTotal: 3,
                filesModified: ["/Users/dev/projects/demo/Sources/App/Parser.swift"],
                turnDuration: 200
            )
        )

        let card = SessionCard(session: session, home: "/Users/loic")

        #expect(card.summaryText == "Fixed the parser crash.\n\n- added a regression test")
        #expect(card.summaryFacts == "todos 1/3 · 1 fichier · 3:20")
    }

    @Test("The facts line only shows what the extraction found")
    func factsLineIsBestEffort() {
        func card(_ summary: TurnSummary?) -> SessionCard {
            SessionCard(
                session: Session(id: "x", state: .ended, agent: "claude-code", lastSummary: summary),
                home: "/Users/loic")
        }

        #expect(card(nil).summaryText == nil)
        #expect(card(nil).summaryFacts == nil)
        #expect(card(TurnSummary(text: "Done.")).summaryFacts == nil)
        #expect(
            card(TurnSummary(filesModified: ["/a/b.swift", "/a/c.swift"])).summaryFacts
                == "2 fichiers")
        #expect(card(TurnSummary(turnDuration: 65)).summaryFacts == "1:05")
    }

    @Test("The Peek carries the Session's Sprite animation (state-encoded, #55)")
    func peekCarriesTheSpriteAnimation() {
        // The transient Peek now shows the Session's mascot (issue #55): its
        // animation encodes the state, the same mapping the Extended cards use.
        func animation(_ state: SessionState) -> SpriteAnimation {
            IslandController.peekAnimation(
                for: Session(id: "x", state: state, agent: "claude-code"))
        }

        #expect(animation(.running) == .working)
        #expect(animation(.idle) == .sleeping)
        #expect(animation(.ended) == .finished)
        #expect(animation(.waiting) == .question)
    }

    @Test("The Peek shows the summary's first line, smartly truncated")
    func peekShowsTheSummaryFirstLine() {
        // First non-empty line wins; markdown list/heading markers are shed.
        #expect(
            SessionCard.peekLine(project: "island", summaryText: "Fixed the parser crash.\n\nDetails below")
                == "island ✓ Fixed the parser crash.")
        #expect(
            SessionCard.peekLine(project: "island", summaryText: "\n## Recap\nAll good")
                == "island ✓ Recap")

        // A long first line is cut on a word boundary with an ellipsis.
        let long = SessionCard.peekLine(
            project: "island",
            summaryText: String(repeating: "word ", count: 40))
        #expect(long.count <= 90)
        #expect(long.hasSuffix("…"))

        // No summary: the Peek keeps its historical fallback.
        #expect(SessionCard.peekLine(project: "island", summaryText: nil) == "island ✓ terminé")
    }

    @Test("The waiting Peek shows a final question, or the call to action (#39)")
    func waitingPeekShowsTheQuestion() {
        // A turn ending on a question: show the question itself.
        #expect(
            SessionCard.waitingPeekLine(project: "island", questionText: "Postgres or SQLite?")
                == "island · attend : \"Postgres or SQLite?\"")

        // The final question line wins over an earlier lead-in line.
        #expect(
            SessionCard.waitingPeekLine(
                project: "island",
                questionText: "I looked into it.\nShall I proceed with option A?")
                == "island · attend : \"Shall I proceed with option A?\"")

        // No question (nil, or a text that does not end on '?'): the historical
        // call to action — a permission/AskUserQuestion wait carries no question.
        #expect(SessionCard.waitingPeekLine(project: "island", questionText: nil)
            == "island ? attend une réponse")
        #expect(SessionCard.waitingPeekLine(project: "island", questionText: "All done.")
            == "island ? attend une réponse")

        // A very long question is cut on a word boundary with an ellipsis.
        let long = SessionCard.waitingPeekLine(
            project: "island",
            questionText: String(repeating: "word ", count: 40) + "?")
        #expect(long.count <= 105)
        #expect(long.hasSuffix("…\""))
    }
}
