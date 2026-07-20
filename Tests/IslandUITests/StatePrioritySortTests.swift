import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Priorité d'état (issue #44): the Extended cards are ordered by how pressing
/// each Session's state is — waiting > terminé > working > idle — with a
/// per-group recency tie-break. The ordering is a pure function of the sessions
/// and is tested here; the animated reordering is checked visually.
@MainActor
struct StatePrioritySortTests {
    private func session(
        _ id: String,
        _ state: SessionState,
        at seconds: TimeInterval = 0
    ) -> Session {
        Session(
            id: id,
            state: state,
            agent: "claude-code",
            lastActivityAt: Date(timeIntervalSince1970: seconds)
        )
    }

    @Test("Cards are ordered waiting > terminé > working > idle")
    func ordersByStatePriority() {
        let sorted = IslandController.sortedByStatePriority([
            session("idle", .idle),
            session("running", .running),
            session("ended", .ended),
            session("waiting", .waiting),
        ])

        #expect(sorted.map(\.id) == ["waiting", "ended", "running", "idle"])
    }

    @Test("Waiting Sessions are ordered oldest first (anti-oubli)")
    func waitingTieBreakOldestFirst() {
        let sorted = IslandController.sortedByStatePriority([
            session("recent", .waiting, at: 300),
            session("oldest", .waiting, at: 100),
            session("middle", .waiting, at: 200),
        ])

        // The Session that has waited the longest sits on top.
        #expect(sorted.map(\.id) == ["oldest", "middle", "recent"])
    }

    @Test("Terminé/working/idle Sessions are ordered freshest first")
    func nonWaitingTieBreakFreshestFirst() {
        func ids(_ state: SessionState) -> [String] {
            IslandController.sortedByStatePriority([
                session("old", state, at: 100),
                session("fresh", state, at: 300),
                session("mid", state, at: 200),
            ]).map(\.id)
        }

        // The latest result on top, the rest below the fold.
        #expect(ids(.ended) == ["fresh", "mid", "old"])
        #expect(ids(.running) == ["fresh", "mid", "old"])
        #expect(ids(.idle) == ["fresh", "mid", "old"])
    }

    @Test("A Session moving to waiting/terminé climbs to the right rank")
    func stateChangeClimbsToRank() {
        let working = session("s", .running, at: 500)
        let others = [session("w", .waiting, at: 100), session("e", .ended, at: 100)]

        // While working, it sits under waiting and terminé.
        #expect(IslandController.sortedByStatePriority(others + [working]).map(\.id)
            == ["w", "e", "s"])

        // Once it ends its turn, it joins the terminé group (ahead of running).
        let ended = session("s", .ended, at: 600)
        #expect(IslandController.sortedByStatePriority([
            session("w", .waiting, at: 100),
            session("r", .running, at: 700),
            ended,
        ]).map(\.id) == ["w", "s", "r"])
    }

    @Test("The order is deterministic: equal cards never reshuffle (no jitter)")
    func orderIsDeterministic() {
        // Same state, same instant: the id tie-break pins a stable order, so a
        // refresh with the sessions in any input order yields the same result.
        let a = session("aaa", .running, at: 200)
        let b = session("bbb", .running, at: 200)
        let c = session("ccc", .running, at: 200)

        #expect(IslandController.sortedByStatePriority([c, a, b]).map(\.id)
            == ["aaa", "bbb", "ccc"])
        #expect(IslandController.sortedByStatePriority([b, c, a]).map(\.id)
            == ["aaa", "bbb", "ccc"])
    }

    // MARK: - Peek selection shares the same Priorité d'état

    @Test("The Peek picks the most pressing newly-marking Session (waiting > terminé)")
    func peekPicksMostPressing() {
        // Waiting outranks terminé, whatever the input order.
        #expect(IslandController.mostPressingForPeek([
            session("e", .ended, at: 300),
            session("w", .waiting, at: 100),
        ])?.id == "w")

        // No waiting: the terminé Session drives the Peek.
        #expect(IslandController.mostPressingForPeek([
            session("e1", .ended, at: 100),
            session("e2", .ended, at: 200),
        ])?.id == "e2")

        // Within the winning group, the latest to arrive wins (preserves the
        // historical "last" selection).
        #expect(IslandController.mostPressingForPeek([
            session("w1", .waiting, at: 100),
            session("w2", .waiting, at: 200),
        ])?.id == "w2")

        // Nothing newly marking: no Peek.
        #expect(IslandController.mostPressingForPeek([]) == nil)
    }
}
