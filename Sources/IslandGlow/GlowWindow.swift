import AppKit
import SwiftUI

/// Borderless transparent window carrying the Liseré. Never interactive:
/// clicks go through, focus is never taken.
public final class GlowWindow: NSWindow {
    override public var canBecomeKey: Bool { false }
    override public var canBecomeMain: Bool { false }

    /// Draws the outline in the given color (nil clears it).
    func apply(color: GlowColor?) {
        contentView = color.map { NSHostingView(rootView: GlowBorderView(color: $0)) }
    }
}

/// Builds the one full-screen Liseré window of a given screen.
public enum GlowWindowFactory {
    @MainActor
    public static func makeWindow(on screen: NSScreen) -> GlowWindow {
        let window = GlowWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // A Liseré that catches a single click makes the Mac unusable.
        window.ignoresMouseEvents = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        // Above standard windows, on every Space, over fullscreen apps.
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.isReleasedWhenClosed = false
        window.setFrame(screen.frame, display: false)
        return window
    }
}

/// The luminous outline itself, macOS screen-selection style: a soft glowing
/// stroke hugging the screen edges. Pixels are checked visually.
struct GlowBorderView: View {
    let color: GlowColor

    private var tint: Color {
        switch color {
        case .orange: Color.orange
        case .green: Color.green
        }
    }

    var body: some View {
        Rectangle()
            .strokeBorder(tint.opacity(0.9), lineWidth: 5)
            .blur(radius: 2)
            .overlay(
                Rectangle()
                    .strokeBorder(tint.opacity(0.5), lineWidth: 14)
                    .blur(radius: 12)
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
}
