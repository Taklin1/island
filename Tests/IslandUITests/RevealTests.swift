import CoreGraphics
import Foundation
import Testing
@testable import IslandUI
import IslandStore

/// Edge-reveal geometry (issue #53, ADR-0007): the floating Island is Masqué by
/// default and only deploys the Extended mode when the cursor is pushed against
/// the top edge, inside a ~280 pt band centred near the webcam, with ≥1 Session.
/// The global `NSEvent` monitor is a thin shell that delegates every decision to
/// the pure `shouldReveal(at:in:sessionCount:)` tested here (the shell itself is
/// covered visually by the FP). Coordinates are Cocoa screen space (origin
/// bottom-left, so the top edge is `maxY`).
@MainActor
struct RevealTests {
    /// A 1440×900 main screen with the menu bar at the top.
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("Cursor pinned to the top edge, centred, with a Session → reveal")
    func revealsAtTopCentreWithSessions() {
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        #expect(IslandController.shouldReveal(at: atEdgeCentre, in: screen, sessionCount: 1))
    }

    @Test("Not pinned to the top edge → no reveal, even centred with Sessions")
    func doesNotRevealBelowTheEdge() {
        let wellBelow = CGPoint(x: screen.midX, y: screen.maxY - 40)
        #expect(!IslandController.shouldReveal(at: wellBelow, in: screen, sessionCount: 2))
    }

    @Test("At the edge but outside the centred band → no reveal")
    func doesNotRevealOutsideTheBand() {
        let farLeft = CGPoint(x: screen.minX + 10, y: screen.maxY)
        let farRight = CGPoint(x: screen.maxX - 10, y: screen.maxY)
        #expect(!IslandController.shouldReveal(at: farLeft, in: screen, sessionCount: 1))
        #expect(!IslandController.shouldReveal(at: farRight, in: screen, sessionCount: 1))
    }

    @Test("Zero Sessions → never reveals, even pinned at the top centre")
    func neverRevealsWithoutSessions() {
        let atEdgeCentre = CGPoint(x: screen.midX, y: screen.maxY)
        #expect(!IslandController.shouldReveal(at: atEdgeCentre, in: screen, sessionCount: 0))
    }

    @Test("Revealing acknowledges no Session — regarder ≠ traiter (#53)")
    func revealAcknowledgesNothing() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "blocked", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let controller = IslandController(store: store)

        controller.reveal()

        #expect(store.sessions[0].needsAcknowledgement == true)
    }
}
