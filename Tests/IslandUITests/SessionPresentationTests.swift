import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Pure presentation logic of the Island (PRD #3, Testing Decisions): the
/// SwiftUI rendering is checked visually, but labels, glyphs and durations
/// are plain functions and are tested here.
@MainActor
struct SessionPresentationTests {
    @Test("The compact bar shows one glyph per Session, in order")
    func compactStatusShowsOneEntryPerSession() {
        let sessions = [
            Session(id: "a", state: .running, agent: "claude-code"),
            Session(id: "b", state: .idle, agent: "claude-code"),
            Session(id: "c", state: .ended, agent: "claude-code"),
        ]

        #expect(IslandController.compactStatus(for: sessions) == "● ○ ✓")
        #expect(IslandController.compactStatus(for: []) == "–")
    }

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
}
