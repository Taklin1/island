import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Announcement memory (issue #132, PRD #129): a (Session, marking state) pair
/// that was already announced stays SILENT — no new Peek — until it is rearmed
/// by an Acknowledgement of that Session or by a real new turn of that Session.
/// This closes the residual hole documented by PR #104: the intra-Peek
/// coalescence (#99) only covers events landing while a Peek is alive; marking
/// events spaced beyond a Peek's life (ADR-0008 gate flips terminé ↔ en cours,
/// identical re-emissions) used to re-surface in a loop. The persistence of
/// attention is carried by the Liseré alone (ADR-0007) — never by repetition.
///
/// Same seam as the #99 tests: drive `sessionsDidChange` directly (bypassing
/// the Combine throttle), assert through `peekSurfaceCount` / `isPeeking` /
/// `peekedSessionID`, and use a short `peekDuration` so the inter-Peek cases
/// (event AFTER the fold) are reached deterministically.
@MainActor
struct AnnouncementMemoryTests {
    /// A Session whose turn just ended, as the real store publishes it: the
    /// marking event awaits Acknowledgement.
    private func ended(_ id: String, lastPrompt: String? = nil) -> Session {
        Session(id: id, state: .ended, cwd: "/tmp/\(id)", agent: "claude-code",
                lastPrompt: lastPrompt, needsAcknowledgement: true)
    }

    /// A Session flipped back to "en cours" by the ADR-0008 gate (a Stop with
    /// live background tasks), as the real store publishes it: the gate branch
    /// touches NEITHER `needsAcknowledgement` (stays true from the announced
    /// ended) NOR `lastPrompt`/`turnStartedAt` — only a real new turn does.
    private func gateRunning(_ id: String, lastPrompt: String? = nil) -> Session {
        Session(id: id, state: .running, cwd: "/tmp/\(id)", agent: "claude-code",
                lastPrompt: lastPrompt, needsAcknowledgement: true,
                activeBackgroundTaskCount: 1)
    }

    /// Polls until the live Peek folds back to Masqué (same shape as the #99
    /// recede test: never a fixed sleep against a contended MainActor).
    private func awaitFold(of controller: IslandController) async {
        for _ in 0..<40 where controller.isPeeking {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("A gate flip spaced beyond the Peek's life re-announces nothing (#132, ADR-0008)")
    func gateFlipBeyondPeekLifeStaysSilent() async {
        let controller = IslandController(store: SessionStore(), peekDuration: .milliseconds(80))

        controller.sessionsDidChange([ended("g")]) // terminé → announced
        #expect(controller.peekSurfaceCount == 1)
        await awaitFold(of: controller)
        #expect(!controller.isPeeking)

        // The residual #104 hole: the same pair re-emerges AFTER the fold.
        controller.sessionsDidChange([gateRunning("g")]) // gate: bg task alive
        controller.sessionsDidChange([ended("g")])       // gate resolves again

        #expect(controller.peekSurfaceCount == 1) // no second surface
        #expect(!controller.isPeeking)            // silent: the Liseré persists, not the Peek
    }

    @Test("A real new turn (UserPromptSubmit) rearms: the next terminé re-announces (#132)")
    func realNewTurnRearmsTheEndedAnnouncement() async {
        let controller = IslandController(store: SessionStore(), peekDuration: .milliseconds(80))

        controller.sessionsDidChange([ended("t", lastPrompt: "first ask")])
        #expect(controller.peekSurfaceCount == 1)
        await awaitFold(of: controller)

        // UserPromptSubmit, as the real store publishes it (SessionStore
        // promptSubmitted): fresh prompt, fresh turn start, flag cleared.
        controller.sessionsDidChange([Session(
            id: "t", state: .running, cwd: "/tmp/t", agent: "claude-code",
            lastPrompt: "second ask", turnStartedAt: Date(),
            needsAcknowledgement: false)])
        #expect(controller.peekSurfaceCount == 1) // the new turn itself announces nothing

        controller.sessionsDidChange([ended("t", lastPrompt: "second ask")])

        #expect(controller.peekSurfaceCount == 2) // a real second result re-announces
        #expect(controller.peekedSessionID == "t")
    }

    @Test("An Acknowledgement rearms: the next attend re-announces, the ack itself is silent (#132)")
    func acknowledgementRearmsTheWaitingAnnouncement() async {
        let controller = IslandController(store: SessionStore(), peekDuration: .milliseconds(80))
        func waiting(_ id: String, acknowledged: Bool) -> Session {
            Session(id: id, state: .waiting, cwd: "/tmp/\(id)", agent: "claude-code",
                    needsAcknowledgement: !acknowledged)
        }

        controller.sessionsDidChange([waiting("w", acknowledged: false)])
        #expect(controller.peekSurfaceCount == 1) // attend announced once
        await awaitFold(of: controller)

        // Acknowledgement (card click / terminal refocus): the store clears
        // the flag WITHOUT touching the state — the Session still waits.
        controller.sessionsDidChange([waiting("w", acknowledged: true)])
        #expect(controller.peekSurfaceCount == 1) // acknowledging never re-Peeks
        #expect(!controller.isPeeking)

        // A fresh blocking event re-raises the flag: rearmed → new Annonce.
        controller.sessionsDidChange([waiting("w", acknowledged: false)])
        #expect(controller.peekSurfaceCount == 2)
        #expect(controller.peekedSessionID == "w")
    }

    @Test("An identical re-emission spaced beyond the Peek's life stays silent (#132)")
    func identicalReemissionBeyondPeekLifeStaysSilent() async {
        let controller = IslandController(store: SessionStore(), peekDuration: .milliseconds(80))

        controller.sessionsDidChange([ended("s")])
        #expect(controller.peekSurfaceCount == 1)
        await awaitFold(of: controller)

        // A non-state event re-published the same terminé (statusline re-emit):
        // beyond the intra-Peek window of #99, the memory keeps it silent.
        controller.sessionsDidChange([ended("s")])

        #expect(controller.peekSurfaceCount == 1)
        #expect(!controller.isPeeking)
    }

    @Test("A new turn coalesced with its Stop by the throttle still rearms (#132)")
    func throttleCoalescedNewTurnStillRearms() async {
        let controller = IslandController(store: SessionStore(), peekDuration: .milliseconds(80))

        controller.sessionsDidChange([ended("c", lastPrompt: "first ask")])
        #expect(controller.peekSurfaceCount == 1)
        await awaitFold(of: controller)

        // The 200 ms throttle can swallow the intermediate running snapshot
        // (prompt + quick Stop in one window): the Session jumps terminé →
        // terminé with only the prompt moved and the flag re-raised. The
        // `lastPrompt` marker is what survives that coalescing.
        controller.sessionsDidChange([ended("c", lastPrompt: "second ask")])

        #expect(controller.peekSurfaceCount == 2)
        #expect(controller.peekedSessionID == "c")
    }
}
