import AppKit
import Testing
@testable import DynamicNotchKit

/// island guard (issue #103), mirror of `IslandGlowTests/GlowWindowTests`: the
/// Liseré window (`GlowWindow`) already carries `.fullScreenAuxiliary` and shows
/// over a full-screen app; the notch panel must too, or the Island stays
/// invisible above a full-screen Space (no Peek, no Reveal). This is a vendored
/// divergence from upstream 1.1.0 — run it via
/// `swift test --package-path Vendor/DynamicNotchKit` (the root gate does not
/// build a path dependency's own test target).
@MainActor
struct DynamicNotchPanelTests {
    @Test("The notch panel is a transparent overlay, above windows, on every Space, over full-screen apps")
    func panelJoinsFullScreenSpaces() {
        let panel = DynamicNotchPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )

        // On every Space…
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        // …and — the fix for #103 — able to join a full-screen app's Space.
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        // Stationary: it does not scroll away with the Spaces.
        #expect(panel.collectionBehavior.contains(.stationary))
        // Above standard windows.
        #expect(panel.level.rawValue > NSWindow.Level.normal.rawValue)
        // Transparent: only the SwiftUI content is drawn.
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.hasShadow)
    }
}
