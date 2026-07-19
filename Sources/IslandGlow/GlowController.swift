import AppKit
import Combine
import Foundation
import IslandStore

/// Drives the Liseré (issue #8) from the session store: lights the screen
/// outline orange when a Session waits on the user, green when one finished,
/// and turns it off on Acknowledgement. One window per screen, always
/// click-through. The preference closure is read live so toggling the Liseré
/// off from the menu applies on the next store change (or `refresh()`).
@MainActor
public final class GlowController {
    private let store: SessionStore
    private let isEnabled: () -> Bool
    private var windows: [GlowWindow] = []
    private var cancellable: AnyCancellable?

    /// Color currently shown by the Liseré (nil = off). Observable behavior:
    /// agentic tests read the matching stdout traces.
    public private(set) var currentColor: GlowColor?

    /// Number of Liseré windows currently on screen.
    public var visibleWindowCount: Int { windows.count(where: \.isVisible) }

    public init(store: SessionStore, isEnabled: @escaping () -> Bool = { true }) {
        self.store = store
        self.isEnabled = isEnabled
    }

    /// Starts following the store. Glow transitions are rare (marking events
    /// and Acknowledgements only), so no throttling is needed.
    public func activate() {
        cancellable = store.$sessions.sink { [weak self] sessions in
            MainActor.assumeIsolated {
                self?.apply(GlowColor.desired(for: sessions, enabled: self?.isEnabled() ?? false))
            }
        }
    }

    /// Re-evaluates the Liseré now (e.g. right after toggling the preference).
    public func refresh() {
        apply(GlowColor.desired(for: store.sessions, enabled: isEnabled()))
    }

    /// Stops following the store and clears the Liseré.
    public func deactivate() {
        cancellable = nil
        apply(nil)
    }

    private func apply(_ color: GlowColor?) {
        guard color != currentColor else { return }
        currentColor = color
        log(color.map { "glow \(String(describing: $0)) on" } ?? "glow off")

        guard let color else {
            windows.forEach { $0.orderOut(nil) }
            return
        }

        // One window per screen, created lazily, kept in sync with displays.
        if windows.count != NSScreen.screens.count {
            windows.forEach { $0.close() }
            windows = NSScreen.screens.map { GlowWindowFactory.makeWindow(on: $0) }
        }
        for (window, screen) in zip(windows, NSScreen.screens) {
            window.setFrame(screen.frame, display: false)
            window.apply(color: color)
            window.orderFrontRegardless()
        }
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("island: [\(timestamp)] \(message)")
    }
}
