import CoreGraphics
import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Geometric recede hardening (issue #60, ADR-0007): the Reveal opens the Étendu
/// *around* the cursor at the top edge, so no native `mouseEntered` fires. If the
/// cursor then leaves without ever hovering the panel, only a **geometric** recede
/// can fold it back to Masqué. The global `NSEvent` monitor stays a thin shell and
/// delegates the decision to the pure `shouldRecede(at:in:keepAliveDepth:)`
/// tested here — the keep-alive depth being derived from the real panel height
/// (#141), like the band width is from the real panel width (#130); the
/// anti-flicker grace and the "not on the panel" guard live in the controller.
/// Coordinates are Cocoa screen space (origin bottom-left, top edge is `maxY`).
@MainActor
struct RecedeTests {
    /// A 1440×900 main screen with the menu bar at the top.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    // MARK: - Pure geometry

    @Test("Cursor drops well below the top edge (centred) → geometric recede")
    func recedesWhenCursorDropsBelowTheEdge() {
        let wayBelow = CGPoint(x: screen.midX, y: screen.maxY - 400)
        #expect(IslandController.shouldRecede(
            at: wayBelow, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
    }

    @Test("Cursor leaves the reveal band horizontally → geometric recede")
    func recedesWhenCursorLeavesTheBand() {
        let farLeft = CGPoint(x: screen.minX + 10, y: screen.maxY)
        let farRight = CGPoint(x: screen.maxX - 10, y: screen.maxY)
        #expect(IslandController.shouldRecede(
            at: farLeft, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
        #expect(IslandController.shouldRecede(
            at: farRight, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
    }

    @Test("Cursor still pinned to the top-centre edge → no recede (still revealing)")
    func doesNotRecedeWhilePinnedAtTheEdge() {
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        #expect(!IslandController.shouldRecede(
            at: atEdgeCentre, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
    }

    @Test("Cursor just under the edge, centred (over the panel) → no recede")
    func doesNotRecedeOverThePanelKeepAliveZone() {
        // Where the deployed panel sits: the native hover keeps it open, the
        // geometric fallback must not fight it.
        let onPanel = CGPoint(x: screen.midX, y: screen.maxY - 80)
        #expect(!IslandController.shouldRecede(
            at: onPanel, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
    }

    @Test("Cursor on the real panel, wider than the content band → no recede (#130)")
    func doesNotRecedeOverTheRealPanelWidth() {
        // The deployed panel is ~380 pt wide (content 340 + the floating style's
        // 20 pt padding each side), wider than the old 340 pt recede band: a
        // cursor skimming its outer edge is ON the panel and must not fold it.
        let onPanelLeftEdge = CGPoint(x: screen.midX - 185, y: screen.maxY - 80)
        let onPanelRightEdge = CGPoint(x: screen.midX + 185, y: screen.maxY - 80)
        #expect(!IslandController.shouldRecede(
            at: onPanelLeftEdge, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
        #expect(!IslandController.shouldRecede(
            at: onPanelRightEdge, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
    }

    @Test("Cursor beyond the real panel plus the hysteresis margin → recede (#130)")
    func recedesBeyondThePanelAndItsMargin() {
        // Past the real panel edge (~190) plus the guaranteed hysteresis margin:
        // clearly off the panel, the geometric fold applies.
        let clearOfPanel = CGPoint(x: screen.midX + 235, y: screen.maxY - 80)
        #expect(IslandController.shouldRecede(
            at: clearOfPanel, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
    }

    @Test("Tall panel: cursor over the low cards, within the derived depth → no recede (#141)")
    func doesNotRecedeOverTheLowCardsOfATallPanel() {
        // Three-plus cards push the panel past the old fixed 220 pt keep-alive:
        // with the depth derived from the real panel height, the low cards are
        // still inside the band and must not fold the panel under the cursor.
        let onLowCards = CGPoint(x: screen.midX, y: screen.maxY - 350)
        #expect(!IslandController.shouldRecede(
            at: onLowCards, in: screen, keepAliveDepth: 380
        ))
    }

    @Test("Tall panel: cursor clearly below the derived depth → recede (#141)")
    func recedesClearlyBelowTheTallPanel() {
        let clearlyBelow = CGPoint(x: screen.midX, y: screen.maxY - 420)
        #expect(IslandController.shouldRecede(
            at: clearlyBelow, in: screen, keepAliveDepth: 380
        ))
    }

    @Test("Keep-alive depth is bounded to the top half of the screen → the recede stays reachable (#141)")
    func keepAliveDepthIsBoundedToHalfTheScreen() {
        // Whatever the caller derives, the band must never swallow the screen:
        // below half the screen height the "clearly dropped away" recede always
        // applies (the vendored window itself never exceeds half a screen).
        let lowerHalf = CGPoint(x: screen.midX, y: screen.maxY - 460)
        #expect(IslandController.shouldRecede(
            at: lowerHalf, in: screen, keepAliveDepth: 10_000
        ))
    }

    @Test("Hysteresis seam: neither reveals nor recedes between the two bands")
    func hysteresisSeamNeitherRevealsNorRecedes() {
        // Just outside the reveal band but inside the wider recede keep-alive
        // band, pinned at the edge: brief oscillation here must not flicker.
        let inSeam = CGPoint(x: screen.midX + 155, y: screen.maxY)
        #expect(!IslandController.shouldReveal(at: inSeam, in: screen, sessionCount: 1))
        #expect(!IslandController.shouldRecede(
            at: inSeam, in: screen,
            keepAliveDepth: IslandController.fallbackRecedeKeepAliveDepth
        ))
    }

    // MARK: - Derived keep-alive depth (#141)

    @Test("Keep-alive depth: fallback before any measurement, panel height + padding + hysteresis after (#141)")
    func derivesKeepAliveDepthFromTheMeasuredPanelHeight() {
        let controller = IslandController(store: SessionStore())

        // Before the view's first layout reports a height: the conservative
        // pre-#141 fallback, never a zero/short band on the first deployment.
        #expect(
            controller.recedeKeepAliveDepth
                == IslandController.fallbackRecedeKeepAliveDepth
        )

        // A tall panel (3+ cards, displayed content 300 pt): the depth covers
        // the real panel — content + 2×20 vendored padding — plus the
        // guaranteed hysteresis margin (#130 pattern).
        controller.panelHeightDidChange(300)
        #expect(controller.recedeKeepAliveDepth == 380)

        // A short panel (1 card): never below the pre-#141 floor — the short
        // panel keeps today's behaviour unchanged.
        controller.panelHeightDidChange(90)
        #expect(
            controller.recedeKeepAliveDepth
                == IslandController.fallbackRecedeKeepAliveDepth
        )
    }

    // MARK: - Controller wiring

    @Test("Reveal, then the cursor clears the band without hovering → folds to Masqué (#60)")
    func geometricRecedeFoldsTheExtended() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        // Zero grace + awaiting the real recede task (#109): no clock margin to
        // race, so the fold is deterministic even under the full parallel suite.
        let controller = IslandController(store: store, recedeGrace: .zero)

        controller.reveal()
        #expect(controller.isExtendedDeployed)

        // The monitor saw the cursor leave the band while the panel is not hovered.
        controller.recedeIfClearOfPanel()
        await controller.settleRecede() // awaits the real fold, no sleep margin

        #expect(!controller.isExtendedDeployed)
    }

    @Test("Scrubbing along the top edge after a fold → at most one cycle (#130)")
    func scrubbingTheEdgeNeverRedeploys() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        // Zero durations + settling every real task (#109): deterministic under
        // the parallel suite. The cooldown is zero on purpose — the re-arm
        // condition alone (the cursor never left the top edge) must block.
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .zero
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        let atEdgeFarRight = CGPoint(x: screen.maxX - 10, y: screen.maxY)

        // Cycle 1: press through the dwell → revealed.
        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        #expect(controller.isExtendedDeployed)

        // Scrub along the edge, out of the band → geometric fold.
        controller.mouseMoved(at: atEdgeFarRight, in: screen, sessionCount: 1)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)
        await controller.settleRecedeCooldown() // even with the cooldown spent…

        // …scrubbing back to the centre without ever leaving the top edge must
        // not redeploy: leaving the edge is the only re-arm.
        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        #expect(!controller.isExtendedDeployed)
    }

    @Test("Leaving the top edge then pressing again → re-Révélation (#130)")
    func leavingTheEdgeThenPressingAgainReveals() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .zero
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        let atEdgeFarRight = CGPoint(x: screen.maxX - 10, y: screen.maxY)
        let offTheEdge = CGPoint(x: screen.midX, y: screen.maxY - 100)

        // Reveal, then fold by scrubbing out of the band along the edge.
        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        controller.mouseMoved(at: atEdgeFarRight, in: screen, sessionCount: 1)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)

        // Leaving the top edge is the new intention that re-arms; coming back
        // to press (through the dwell, cooldown spent) reveals again.
        controller.mouseMoved(at: offTheEdge, in: screen, sessionCount: 1)
        await controller.settleRecedeCooldown()
        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()

        #expect(controller.isExtendedDeployed)
    }

    @Test("A hover-off fold disarms the Révélation like a geometric one (#130)")
    func hoverOffFoldAlsoDisarmsTheReveal() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .zero
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        let onPanel = CGPoint(x: screen.midX, y: screen.maxY - 80)

        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        #expect(controller.isExtendedDeployed)

        // The cursor settles on the panel, then the native hover-off folds the
        // Étendu (the second fold path).
        controller.mouseMoved(at: onPanel, in: screen, sessionCount: 1)
        controller.hoverDidChange(false)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)
        await controller.settleRecedeCooldown()

        // Back to the edge without a fresh leave since the fold: pressing must
        // not redeploy.
        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        #expect(!controller.isExtendedDeployed)
    }

    @Test("Spurious hover-off while still pressed at the edge → no fold (#130)")
    func spuriousHoverOffWhilePressedFoldsNothing() async {
        // The deploy animation can flip the native hover true→false while the
        // cursor stays pinned at the top edge (the panel slides under it, no
        // mouse event fires): that hover-off is spurious — folding would put
        // the pli right under the pressed cursor and the cooldown would then
        // kill the press. The last observed cursor sample vetoes the arming;
        // the geometric path folds when the cursor actually leaves.
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .zero
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)

        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        #expect(controller.isExtendedDeployed)

        // Hover flips off while the cursor never moved off the edge.
        controller.hoverDidChange(false)
        await controller.settleRecede()

        #expect(controller.isExtendedDeployed) // still pressed → still deployed
    }

    @Test("Hover-on during the post-fold cooldown never redeploys the Étendu (#145)")
    func hoverDuringCooldownDoesNotRedeploy() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        // A long cooldown keeps the post-fold window unambiguously open while
        // the parasite hover lands; it is deliberately never settled — the
        // assertion is the absence of a redeploy DURING the cooldown.
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .seconds(60)
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        let onPanel = CGPoint(x: screen.midX, y: screen.maxY - 80)

        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        #expect(controller.isExtendedDeployed)

        // The cursor settles on the panel, then the native hover-off folds the
        // Étendu (the #145 timeline's legitimate fold).
        controller.mouseMoved(at: onPanel, in: screen, sessionCount: 1)
        controller.hoverDidChange(false)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)

        // The half-screen vendored window, still fading out under the cursor,
        // fires the parasite hover-on (#145): Masqué + cooldown running → the
        // promotion must be gated like pressToReveal, no redeploy.
        controller.hoverDidChange(true)
        #expect(!controller.isExtendedDeployed)
    }

    @Test("Cooldown spent but cursor never left the edge → hover-on still ignored (#145)")
    func hoverAfterCooldownWithoutRearmDoesNotRedeploy() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .zero
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        let onPanel = CGPoint(x: screen.midX, y: screen.maxY - 80)

        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        controller.mouseMoved(at: onPanel, in: screen, sessionCount: 1)
        controller.hoverDidChange(false)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)
        await controller.settleRecedeCooldown() // even with the cooldown spent…

        // …the pump's cursor is immobile: it never left the top edge since the
        // fold, so the Révélation is not re-armed — like the press path (#130),
        // the hover promotion must stay silent.
        controller.hoverDidChange(true)
        #expect(!controller.isExtendedDeployed)
    }

    @Test("Re-armed after the fold → the hover promotion works again (#145)")
    func hoverPromotionWorksAgainAfterRearm() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .zero
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        let onPanel = CGPoint(x: screen.midX, y: screen.maxY - 80)
        let offTheEdge = CGPoint(x: screen.midX, y: screen.maxY - 400)

        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        controller.mouseMoved(at: onPanel, in: screen, sessionCount: 1)
        controller.hoverDidChange(false)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)

        // Leaving the top edge re-arms (#130) and the cooldown elapses: a
        // genuine hover on a live window must promote again, exactly as today.
        controller.mouseMoved(at: offTheEdge, in: screen, sessionCount: 1)
        await controller.settleRecedeCooldown()
        controller.hoverDidChange(true)
        #expect(controller.isExtendedDeployed)
    }

    @Test("A Peek surfaced during the post-fold cooldown still promotes on hover (#145, #99)")
    func hoveredPeekStillPromotesDuringCooldown() async {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        // A long, never-settled cooldown: the Peek path must bypass the #145
        // hover gate entirely (its fold never posts the cooldown, #99).
        let controller = IslandController(
            store: store, recedeGrace: .zero,
            dwellDuration: .zero, recedeCooldown: .seconds(60)
        )
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        let onPanel = CGPoint(x: screen.midX, y: screen.maxY - 80)

        // Deploy then fold: the gate is now armed (cooldown running, disarmed).
        controller.mouseMoved(at: atEdgeCentre, in: screen, sessionCount: 1)
        await controller.settleDwell()
        controller.mouseMoved(at: onPanel, in: screen, sessionCount: 1)
        controller.hoverDidChange(false)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)

        // A marking event surfaces a Peek; hovering it is a deliberate gesture
        // on a visible panel — the promotion must survive the cooldown.
        controller.sessionsDidChange([Session(
            id: "p", state: .ended, cwd: "/tmp/p", agent: "claude-code",
            needsAcknowledgement: true
        )])
        #expect(controller.isPeeking)
        controller.hoverDidChange(true)
        #expect(controller.isExtendedDeployed)
    }

    @Test("Tall panel deployed: the low cards keep it alive, clearly below folds it (#141)")
    func tallPanelLowCardsKeepTheExtendedAlive() async {
        let store = SessionStore()
        // Three Sessions: the panel outgrows the old fixed 220 pt keep-alive —
        // exactly the population the pre-#141 band folded under the cursor.
        for id in ["s1", "s2", "s3"] {
            store.apply(AgentEvent(
                sessionID: id, kind: .waitingForUser(message: nil),
                terminal: "ghostty", agent: "claude-code"
            ))
        }
        let controller = IslandController(store: store, recedeGrace: .zero)

        controller.reveal()
        // The deploy's first layout reported the displayed panel content: the
        // keep-alive depth now derives from the real height (300 → 380).
        controller.panelHeightDidChange(300)
        #expect(controller.isExtendedDeployed)

        // Cursor loitering over the low cards — deeper than the old fixed
        // 220 pt, still on the panel: no recede must arm.
        let onLowCards = CGPoint(x: screen.midX, y: screen.maxY - 350)
        controller.mouseMoved(at: onLowCards, in: screen, sessionCount: 3)
        await controller.settleRecede() // no recede armed → returns immediately
        #expect(controller.isExtendedDeployed)

        // Clearly below the derived depth + margin: the legitimate fold.
        let clearlyBelow = CGPoint(x: screen.midX, y: screen.maxY - 420)
        controller.mouseMoved(at: clearlyBelow, in: screen, sessionCount: 3)
        await controller.settleRecede()
        #expect(!controller.isExtendedDeployed)
    }

    @Test("Geometric recede is a no-op when the Étendu is not deployed (#60)")
    func geometricRecedeIgnoredWhenHidden() async {
        let controller = IslandController(store: SessionStore())

        controller.recedeIfClearOfPanel()
        await controller.settleRecede() // no recede armed → returns immediately

        #expect(!controller.isExtendedDeployed)
    }
}
