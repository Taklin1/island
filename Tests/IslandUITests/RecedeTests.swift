import CoreGraphics
import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Geometric recede hardening (issue #60, ADR-0007): the Reveal opens the Étendu
/// *around* the cursor at the top edge, so no native `mouseEntered` fires. If the
/// cursor then leaves without ever hovering the panel, only a **geometric** recede
/// can fold it back to Masqué. The global `NSEvent` monitor stays a thin shell and
/// delegates the decision to the pure `shouldRecede(at:in:)` tested here; the
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
        #expect(IslandController.shouldRecede(at: wayBelow, in: screen))
    }

    @Test("Cursor leaves the reveal band horizontally → geometric recede")
    func recedesWhenCursorLeavesTheBand() {
        let farLeft = CGPoint(x: screen.minX + 10, y: screen.maxY)
        let farRight = CGPoint(x: screen.maxX - 10, y: screen.maxY)
        #expect(IslandController.shouldRecede(at: farLeft, in: screen))
        #expect(IslandController.shouldRecede(at: farRight, in: screen))
    }

    @Test("Cursor still pinned to the top-centre edge → no recede (still revealing)")
    func doesNotRecedeWhilePinnedAtTheEdge() {
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        #expect(!IslandController.shouldRecede(at: atEdgeCentre, in: screen))
    }

    @Test("Cursor just under the edge, centred (over the panel) → no recede")
    func doesNotRecedeOverThePanelKeepAliveZone() {
        // Where the deployed panel sits: the native hover keeps it open, the
        // geometric fallback must not fight it.
        let onPanel = CGPoint(x: screen.midX, y: screen.maxY - 80)
        #expect(!IslandController.shouldRecede(at: onPanel, in: screen))
    }

    @Test("Hysteresis seam: neither reveals nor recedes between the two bands")
    func hysteresisSeamNeitherRevealsNorRecedes() {
        // Just outside the reveal band but inside the wider recede keep-alive
        // band, pinned at the edge: brief oscillation here must not flicker.
        let inSeam = CGPoint(x: screen.midX + 155, y: screen.maxY)
        #expect(!IslandController.shouldReveal(at: inSeam, in: screen, sessionCount: 1))
        #expect(!IslandController.shouldRecede(at: inSeam, in: screen))
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

    @Test("Geometric recede is a no-op when the Étendu is not deployed (#60)")
    func geometricRecedeIgnoredWhenHidden() async {
        let controller = IslandController(store: SessionStore())

        controller.recedeIfClearOfPanel()
        await controller.settleRecede() // no recede armed → returns immediately

        #expect(!controller.isExtendedDeployed)
    }
}
