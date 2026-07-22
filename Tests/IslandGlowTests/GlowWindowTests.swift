import AppKit
import Testing
import IslandGlow

@MainActor
struct GlowWindowTests {
    @Test("The Liseré window is full-screen, click-through, above standard windows, on every Space")
    func windowIsClickThroughAndFullScreen() throws {
        let screen = try #require(NSScreen.screens.first, "needs a screen to run")

        let window = GlowWindowFactory.makeWindow(on: screen)
        defer { window.close() }

        // A Liseré that catches a single click makes the Mac unusable.
        #expect(window.ignoresMouseEvents)
        // Full-screen outline: the window covers the whole screen.
        #expect(window.frame == screen.frame)
        // Above standard windows…
        #expect(window.level.rawValue > NSWindow.Level.normal.rawValue)
        // …on every Space, and over fullscreen apps.
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(window.collectionBehavior.contains(.fullScreenAuxiliary))
        // Transparent: only the outline is drawn.
        #expect(!window.isOpaque)
        #expect(window.backgroundColor == .clear)
        #expect(!window.hasShadow)
        // Never steals focus.
        #expect(!window.canBecomeKey)
        #expect(!window.canBecomeMain)
    }
}
