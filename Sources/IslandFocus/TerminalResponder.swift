import AppKit
import ApplicationServices
import Foundation

/// The physical keystroke that selects an AskUserQuestion option in the Claude
/// Code TUI when answering a blocked Session from the Island (issue #27).
///
/// v1-frozen mapping: the option's **1-based number**, then **Return** — the
/// same 1/2/3 the card shows, so what is injected matches what the user taps.
/// The exact live-TUI sequence (a bare digit vs digit-then-Return, multi-select
/// toggles, the harness-added "Other") is confirmed and tuned on the running
/// TUI during the HITL injection FP; keeping it here, off the targeting guard,
/// means that tuning never weakens the "certain target or nothing" safety.
public struct AnswerKeystroke: Equatable {
    /// Characters typed to select the option (the 1-based number).
    public let characters: String
    /// Whether Return is sent after the characters to confirm the selection.
    public let sendsReturn: Bool

    public init(optionIndex: Int) {
        characters = String(optionIndex + 1)
        sendsReturn = true
    }
}

/// One Ghostty window discovered for targeting (issue #27, spike #25): the cwd
/// it exposes via the Accessibility `AXDocument` attribute, and the action that
/// brings it frontmost so an injected keystroke lands in it. The action is
/// built by the `.live` responder from the window's `AXUIElement`; tests pass a
/// recording stand-in, so no real window is ever raised in a unit test.
public struct TerminalWindow {
    /// The window's cwd (`AXDocument` file URL), or `nil` when it exposed none.
    public let cwd: String?
    /// Raises this window and activates its app so the keystroke reaches it.
    public let raiseAndActivate: () -> Void

    public init(cwd: String?, raiseAndActivate: @escaping () -> Void) {
        self.cwd = cwd
        self.raiseAndActivate = raiseAndActivate
    }
}

/// Answers a blocked Session from the Island by injecting the chosen option's
/// keystroke into its terminal — but **only** when that terminal is a certain
/// target (issue #27, ADR-0009). The targeting guard
/// (``GhosttyWindowTargeting``) and the OS side-effects (enumerating windows,
/// raising one, posting the `CGEvent`) are separate injectable seams, so the
/// decision is unit-tested while the real Accessibility/CGEvent posting — which
/// the spike proved must never run against the live Ghostty — lives only in
/// ``live`` and is exercised solely by the HITL FP.
@MainActor
public struct TerminalResponder {
    /// Whether the process holds Accessibility trust (`AXIsProcessTrusted`);
    /// without it, reading windows and posting events is impossible → degrade.
    let isTrusted: () -> Bool
    /// Enumerates the open Ghostty windows and their `AXDocument` cwds.
    let listWindows: () -> [TerminalWindow]
    /// Posts the keystroke to the frontmost window (the one just raised).
    let postKeystroke: (AnswerKeystroke) -> Void

    public init(
        isTrusted: @escaping () -> Bool,
        listWindows: @escaping () -> [TerminalWindow],
        postKeystroke: @escaping (AnswerKeystroke) -> Void
    ) {
        self.isTrusted = isTrusted
        self.listWindows = listWindows
        self.postKeystroke = postKeystroke
    }

    /// Injects the option's keystroke into the Session's terminal **iff** the
    /// targeting guard reports exactly one Ghostty window at the Session's cwd,
    /// and Accessibility is trusted. Returns whether it injected: `false` means
    /// nothing was posted (uncertain target, no trust, or unknown cwd) and the
    /// caller must degrade to Click-to-focus — a keystroke never lands in a
    /// terminal we are not certain of.
    public func inject(optionIndex: Int, forSessionCWD cwd: String?) -> Bool {
        guard isTrusted(), let cwd else { return false }
        let windows = listWindows()
        guard case let .certain(index) = GhosttyWindowTargeting.verdict(
            forSessionCWD: cwd, amongst: windows.map(\.cwd))
        else { return false }
        windows[index].raiseAndActivate()
        postKeystroke(AnswerKeystroke(optionIndex: optionIndex))
        return true
    }
}

// MARK: - Production seam (Accessibility + CGEvent)

extension TerminalResponder {
    /// Production responder backed by the Accessibility API and `CGEvent`. This
    /// is the **only** code that touches the real APIs. Per the spike #25 safety
    /// rule — a stray synthetic keystroke to the *live* Ghostty closed every one
    /// of Loïc's windows — it is exercised **solely by the HITL injection FP** on
    /// the packaged `island.app` against a disposable target, never in a unit
    /// test and never from a script against the working instance.
    public static let live = TerminalResponder(
        isTrusted: { AXIsProcessTrusted() },
        listWindows: liveGhosttyWindows,
        postKeystroke: livePostKeystroke
    )
}

/// Bundle identifier of the only terminal v1 targets (spike #25). The exact
/// window/tab enumeration below is the shared mechanism **#36 reuses** (focus
/// the exact window, not just the app) instead of growing a second one.
private let ghosttyBundleID = "com.mitchellh.ghostty"

/// Enumerates every window of every running Ghostty instance and reads the cwd
/// each exposes via `AXDocument` (spike #25), paired with its raise action.
/// Iterates **all** instances of the bundle — a second instance (`open -n`)
/// would otherwise hide its windows from a first-instance-only scan.
private func liveGhosttyWindows() -> [TerminalWindow] {
    var windows: [TerminalWindow] = []
    for app in NSRunningApplication.runningApplications(withBundleIdentifier: ghosttyBundleID) {
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
            windows.append(TerminalWindow(cwd: cwd) {
                // Certain target only (the caller vetted unicity): raise the
                // window and activate Ghostty — this gives focus TO the terminal
                // (never to the Island panel), so the non-activating invariant
                // holds and the keystroke lands in the frontmost, right window.
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                app.activate()
            })
        }
    }
    return windows
}

/// Posts the answer keystroke as `CGEvent`s to the just-raised frontmost window:
/// the option characters as a unicode string, then Return (virtual key 36) when
/// asked. The exact sequence is tuned against the live TUI during the HITL FP.
private func livePostKeystroke(_ keystroke: AnswerKeystroke) {
    let source = CGEventSource(stateID: .combinedSessionState)
    let utf16 = Array(keystroke.characters.utf16)
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
        event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        event?.post(tap: .cghidEventTap)
    }
    guard keystroke.sendsReturn else { return }
    let returnKey: CGKeyCode = 36
    CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)?
        .post(tap: .cghidEventTap)
    CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)?
        .post(tap: .cghidEventTap)
}
