import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Peek coalescence under bursts (issue #99, ADR-0007): when marking events
/// arrive faster than a Peek's life, the Island must surface ONE continuous
/// Peek (content updated in place) instead of tearing the panel down and
/// redeploying it per event — the "ça pompe" monte/descend. The Peek stays
/// transient (it recedes a Peek's duration after the *last* event) and
/// acknowledges nothing; the persistence of attention stays on the Liseré.
///
/// The window monte/descend has no reachable signal without a real panel, so
/// the tests assert it through `peekSurfaceCount` (how many times a *new* Peek
/// was surfaced from Masqué) and drive the exact burst through the throttled
/// sink handler `sessionsDidChange`, bypassing the Combine throttle.
@MainActor
struct PeekCoalescenceTests {
    private func ended(_ id: String) -> Session {
        Session(id: id, state: .ended, cwd: "/tmp/\(id)", agent: "claude-code",
                needsAcknowledgement: true)
    }

    private func running(_ id: String) -> Session {
        Session(id: id, state: .running, cwd: "/tmp/\(id)", agent: "claude-code")
    }

    @Test("A burst from different Sessions coalesces into one continuous surface (#99)")
    func burstFromDifferentSessionsSurfacesOnce() {
        let controller = IslandController(store: SessionStore())

        // Four Sessions finish within a Peek's life (default 2.5 s), each its
        // own throttled batch — the multi-session burst shape of #99.
        controller.sessionsDidChange([ended("a")])
        controller.sessionsDidChange([ended("a"), ended("b")])
        controller.sessionsDidChange([ended("a"), ended("b"), ended("c")])
        controller.sessionsDidChange([ended("a"), ended("b"), ended("c"), ended("d")])

        #expect(controller.peekSurfaceCount == 1) // ONE monte, not four
        #expect(controller.isPeeking)             // still the single surface
        #expect(controller.peekedSessionID == "d") // Sprite swapped to the latest
    }

    @Test("A same-Session gate flip (ended→running→ended) coalesces, no re-Peek (#99, ADR-0008)")
    func sameSessionGateFlipSurfacesOnce() {
        let controller = IslandController(store: SessionStore())

        // The suspected phantom source (piste #1): a Session that a live
        // Sous-agent keeps flipping terminé ↔ en cours. Each re-entry into
        // "terminé" within the Peek's life must extend the one surface, not
        // fold-and-redeploy it.
        controller.sessionsDidChange([ended("z")])   // terminé → Peek
        controller.sessionsDidChange([running("z")]) // gate flips back to en cours
        controller.sessionsDidChange([ended("z")])   // terminé again, still peeking

        #expect(controller.peekSurfaceCount == 1) // the re-ended coalesced, no monte
        #expect(controller.isPeeking)
        #expect(controller.peekedSessionID == "z")
    }

    @Test("The same marking state re-emitted by the same Session fires no new Peek (#99)")
    func sameStateReemittedFiresNoNewPeek() {
        let controller = IslandController(store: SessionStore())

        // A Session that stays terminé, re-published (a non-state event touched
        // it, the statusline re-emitted): it is not *newly* marking, so no Peek
        // beyond the first — the source-level dedup that must hold under the
        // coalescence change too.
        controller.sessionsDidChange([ended("s")])
        controller.sessionsDidChange([ended("s")])
        controller.sessionsDidChange([ended("s")])

        #expect(controller.peekSurfaceCount == 1)
        #expect(controller.peekedSessionID == "s")
    }

    @Test("The single surface recedes a Peek's duration after the last event (#99, ADR-0007)")
    func surfaceRecedesAfterTheBurstEnds() async {
        let controller = IslandController(store: SessionStore(), peekDuration: .milliseconds(80))

        controller.sessionsDidChange([ended("a")])
        controller.sessionsDidChange([ended("a"), ended("b")]) // re-arms the recede
        #expect(controller.isPeeking)

        // Poll rather than a fixed sleep: the recede fires ~80 ms after the last
        // event, but the MainActor can be contended under the full parallel
        // suite — wait up to ~2 s, returning as soon as it folds.
        for _ in 0..<40 where controller.isPeeking {
            try? await Task.sleep(for: .milliseconds(50))
        }
        #expect(!controller.isPeeking)            // folded back to Masqué, transient
        #expect(controller.peekSurfaceCount == 1) // and it was one surface all along
    }

    @Test("No Peek surfaces while the Étendu is revealed (#99, ADR-0007)")
    func noPeekWhileExtended() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "a", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"))
        let controller = IslandController(store: store)

        controller.reveal() // Étendu deployed (Reveal owns the panel)
        #expect(controller.isExtendedDeployed)

        controller.sessionsDidChange([ended("a")]) // a marking event lands

        #expect(controller.peekSurfaceCount == 0) // no Peek fights the Reveal
        #expect(controller.isExtendedDeployed)     // still Étendu
    }
}
