import AppKit
import ApplicationServices

/// The one shared Ghostty window/tab enumeration (spike #25): both the
/// injection (``TerminalResponder``) and Click-to-focus (``TerminalFocuser``,
/// issue #36) target windows through this seam — a single window/tab mechanism,
/// never two. Real AX reads live only here and are exercised by the HITL FPs,
/// never by a unit test.
enum GhosttyWindows {
    /// Bundle identifier of the only terminal v1 targets (spike #25).
    static let bundleID = "com.mitchellh.ghostty"

    /// Enumerates every window of every running Ghostty instance and reads the
    /// cwd each exposes via `AXDocument` (spike #25), paired with its owning
    /// pid and its raise action. Iterates **all** instances of the bundle — a
    /// second instance (`open -n`) would otherwise hide its windows from a
    /// first-instance-only scan.
    static func live() -> [TerminalWindow] {
        var windows: [TerminalWindow] = []
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                appElement, kAXWindowsAttribute as CFString, &value) == .success,
                let axWindows = value as? [AXUIElement]
            else { continue }
            for window in axWindows {
                var document: CFTypeRef?
                let read = AXUIElementCopyAttributeValue(
                    window, kAXDocumentAttribute as CFString, &document)
                let cwd = read == .success ? document as? String : nil
                windows.append(TerminalWindow(cwd: cwd, pid: app.processIdentifier) {
                    // Certain target only (the caller vetted unicity): raise the
                    // window and activate Ghostty — the Session's terminal comes
                    // frontmost, whether the tap was a card click (#36) or an
                    // answer (#27). Delivery never depends on this activation
                    // being effective (#81): the keystroke is posted to the pid
                    // only after `liveObserveFrontTerminal` confirms it.
                    AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                    app.activate()
                })
            }
        }
        return windows
    }
}
