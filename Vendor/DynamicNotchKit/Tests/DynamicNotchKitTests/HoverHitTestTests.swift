import CoreGraphics
import Testing
@testable import DynamicNotchKit

/// island guard (issue #145): the floating panel's window spans half the
/// screen (`initializeWindow`: `screen.frame.width / 2`), far wider than the
/// visible panel. While that window fades out (or is re-created) under a
/// cursor parked inside its frame but OUTSIDE the visible panel, SwiftUI's
/// `onHover` fires a parasite `true` (measured up to 237 pt off-centre on a
/// ~205 pt half-panel — the 0.1.34 residual pump's engine). The vendored fix
/// hit-tests the reported hover against the hover view's REAL frame before
/// accepting it; this suite pins the pure predicate. Coordinates: the mouse
/// arrives in AppKit window space (origin bottom-left), the region in SwiftUI
/// global space (origin top-left) — the predicate owns the Y flip.
/// This is a vendored divergence from upstream 1.1.0 — run it via
/// `swift test --package-path Vendor/DynamicNotchKit` (the root gate does not
/// build a path dependency's own test target).
struct HoverHitTestTests {
    /// The #145 shape: a 720×450 half-screen window (1440×900 logical screen)
    /// whose visible hover view (content + paddings) is a ~410 pt wide,
    /// 250 pt tall block centred at the top.
    private let windowHeight: CGFloat = 450
    private let hoverRegion = CGRect(x: 155, y: 0, width: 410, height: 250)

    @Test("Mouse genuinely on the panel → hover accepted")
    func acceptsMouseOnThePanel() {
        // Centre of the panel: AppKit y=400 in a 450-high window flips to
        // SwiftUI y=50, well inside the region.
        #expect(HoverHitTest.accepts(
            mouseInWindow: CGPoint(x: 360, y: 400),
            windowHeight: windowHeight,
            hoverRegion: hoverRegion
        ))
    }

    @Test("Mouse in the window frame but beside the panel → hover rejected (#145 dead zone)")
    func rejectsMouseBesideThePanel() {
        // The instrumented pump: cursor pinned at the top edge, 237 pt right
        // of centre — inside the half-screen window (±360), outside the
        // visible panel (±205). The parasite hover-on must be rejected.
        #expect(!HoverHitTest.accepts(
            mouseInWindow: CGPoint(x: 360 + 237, y: 450),
            windowHeight: windowHeight,
            hoverRegion: hoverRegion
        ))
    }

    @Test("Mouse below the panel, still in the window frame → hover rejected")
    func rejectsMouseBelowThePanel() {
        // AppKit y=10 (window bottom) flips to SwiftUI y=440 — under the
        // 250 pt panel block: the Y flip is what makes this case reject.
        #expect(!HoverHitTest.accepts(
            mouseInWindow: CGPoint(x: 360, y: 10),
            windowHeight: windowHeight,
            hoverRegion: hoverRegion
        ))
    }

    @Test("Edge of the hover view counts as on it (no dead border)")
    func acceptsMouseOnTheRegionEdge() {
        // Skimming the panel's outer edge is ON the panel (#130's lesson):
        // the region's leading/top boundary itself must accept (cursor pinned
        // at the very top edge, on the panel's left rim).
        #expect(HoverHitTest.accepts(
            mouseInWindow: CGPoint(x: 155, y: 450),
            windowHeight: windowHeight,
            hoverRegion: hoverRegion
        ))
    }
}
