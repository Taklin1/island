import DynamicNotchKit
import IslandStore
import SwiftUI
import Testing
@testable import IslandUI

/// Height cap of the Extended panel (#43): the Session list scrolls once it
/// would exceed ~1/4 of the screen, and hugs its content below that — never
/// leaving empty space with 1–2 Sessions. The scrolling gesture and the fact
/// that it never activates the panel are checked visually / by
/// ``FirstMouseTests``; the cap arithmetic is a plain function and is pinned
/// here.
@MainActor
struct ExpandedPanelHeightTests {
    @Test("Below the cap the panel hugs its content, leaving no empty space")
    func hugsContentBelowCap() {
        // A short list (a couple of cards) well under a quarter screen keeps its
        // intrinsic height, so 1–2 Sessions never sit in a half-empty panel.
        let height = SessionCardsView.cappedHeight(contentHeight: 120, screenHeight: 1000)
        #expect(height == 120)
    }

    @Test("Above the cap the panel stops at ~1/4 of the screen so the rest scrolls")
    func capsAtAQuarterScreen() {
        // A tall list (many Sessions) clamps to the cap; the overflow is reached
        // by scrolling. 250 = 0.25 * 1000.
        let height = SessionCardsView.cappedHeight(contentHeight: 800, screenHeight: 1000)
        #expect(height == 250)
    }

    @Test("The scrollable Session list lives inside the non-activating, first-mouse host")
    func scrollableListNeverStealsFocus() {
        // The Extended list is now a ScrollView (#43). Scrolling or clicking it
        // must never make the Island the active app: it is hosted in the same
        // `.nonactivatingPanel` `FirstMouseHostingView` as before (issue #33),
        // so `scrollWheel`/`mouseDown` reach the content without activation.
        let model = IslandViewModel()
        model.showCards = true
        model.cards = (0 ..< 12).map { index in
            SessionCard(
                session: Session(id: "s\(index)", state: .running, cwd: "/tmp/p\(index)", agent: "claude-code"),
                home: "/Users/loic"
            )
        }
        let host = FirstMouseHostingView(rootView: SessionCardsView(model: model))
        #expect(host.acceptsFirstMouse(for: nil) == true)
    }
}
