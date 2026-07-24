//
//  HoverHitTest.swift
//  DynamicNotchKit
//
//  island patch (issue #145): real hit-test for hover-on reports.
//

import CoreGraphics

/// island patch (issue #145): the floating panel's window spans half the
/// screen (`DynamicNotch.initializeWindow`), far wider than the visible
/// panel. While that window fades out or is re-created with the cursor
/// parked inside its frame but outside the visible panel, SwiftUI's
/// `onHover` can fire a parasite `true` (observed up to ~270 pt off-centre
/// on a ~205 pt half-panel — the engine of the 0.1.34 residual pump). This
/// pure predicate decides whether a hover-on report is genuine: the mouse
/// must actually lie inside the hover view's real frame. Not upstream —
/// remove/reconcile if switching back to the package URL. Guard:
/// `Tests/DynamicNotchKitTests/HoverHitTestTests`.
enum HoverHitTest {
    /// Whether a reported hover-on is genuine.
    /// - Parameters:
    ///   - mouseInWindow: the mouse location in AppKit window coordinates
    ///     (origin bottom-left — `NSWindow.convertPoint(fromScreen:)`).
    ///   - windowHeight: the window's frame height, used to flip into
    ///     SwiftUI's top-left-origin space.
    ///   - hoverRegion: the hover view's frame in SwiftUI global
    ///     coordinates (top-left origin), as measured by the view itself.
    /// - Returns: `true` when the mouse genuinely lies on the hover view.
    static func accepts(
        mouseInWindow: CGPoint,
        windowHeight: CGFloat,
        hoverRegion: CGRect
    ) -> Bool {
        let mouseInSwiftUISpace = CGPoint(
            x: mouseInWindow.x,
            y: windowHeight - mouseInWindow.y
        )
        // `CGRect.contains` excludes maxX/maxY: nudge the region so a cursor
        // pinned exactly on the trailing/bottom rim still counts as ON it.
        return hoverRegion.insetBy(dx: -0.5, dy: -0.5).contains(mouseInSwiftUISpace)
    }
}
