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
/// it exposes via the Accessibility `AXDocument` attribute, the pid of the
/// Ghostty instance that owns it (the delivery route of #81), and the action
/// that brings it frontmost. The action is built by the `.live` responder from
/// the window's `AXUIElement`; tests pass a recording stand-in, so no real
/// window is ever raised in a unit test.
public struct TerminalWindow {
    /// The window's cwd (`AXDocument` file URL), or `nil` when it exposed none.
    public let cwd: String?
    /// The pid of the Ghostty instance owning this window: the keystroke is
    /// posted to this pid (never to "whatever has focus"), so it can never
    /// leak to another app (issue #81).
    public let pid: pid_t
    /// Raises this window and activates its app so the user sees the answer
    /// land where they expect.
    public let raiseAndActivate: () -> Void

    public init(cwd: String?, pid: pid_t = 0, raiseAndActivate: @escaping () -> Void) {
        self.cwd = cwd
        self.pid = pid
        self.raiseAndActivate = raiseAndActivate
    }
}

/// The freshest observable state of a Ghostty instance's key window, re-read at
/// the instant of delivery (issue #81): the capture proved a "certain" verdict
/// only means "the visible tab was at the Session's cwd when enumerated" — so
/// the responder re-verifies right before posting, and refuses to post blind.
public struct FrontTerminalObservation {
    /// Whether the Ghostty instance is the active (frontmost) app — the user
    /// is looking at the Space where the answer will land.
    public let isAppActive: Bool
    /// The `AXDocument` file URL of the instance's key window (its visible tab).
    public let keyWindowDocument: String?
    /// The `AXTitle` of the key window: a Claude Code Session always rewrites
    /// it, so a bare `~/path` title is the signature of a plain shell (#81's
    /// anti-bare-shell guard).
    public let keyWindowTitle: String?

    public init(isAppActive: Bool, keyWindowDocument: String?, keyWindowTitle: String?) {
        self.isAppActive = isAppActive
        self.keyWindowDocument = keyWindowDocument
        self.keyWindowTitle = keyWindowTitle
    }
}

/// Truthful outcome of an injection attempt (issue #81): the caller only shows
/// "en cours" on `.injected`, which is returned **iff** the keystroke was
/// actually posted to a verified target — never optimistically.
public enum InjectionOutcome: Equatable, Sendable {
    /// The keystroke was posted to the verified target's pid.
    case injected
    /// The targeting guard refused (no trust, unknown cwd, zero or several
    /// matching windows): nothing was raised, nothing was posted.
    case uncertainTarget
    /// The target was certain and raised, but its live state never confirmed
    /// within the delivery budget (app not active, visible tab moved off the
    /// cwd, or a bare-shell tab in front): nothing was posted.
    case deliveryUnverified
}

/// Answers a blocked Session from the Island by injecting the chosen option's
/// keystroke into its terminal — but **only** when that terminal is a certain
/// target (issue #27, ADR-0009) **and** its live state is re-verified at the
/// instant of delivery (issue #81). The targeting guard
/// (``GhosttyWindowTargeting``) and the OS side-effects (enumerating windows,
/// raising one, observing the front terminal, posting the `CGEvent`) are
/// separate injectable seams, so the decision is unit-tested while the real
/// Accessibility/CGEvent posting — which the spike proved must never run
/// against the live Ghostty — lives only in ``live`` and is exercised solely
/// by the HITL FP.
@MainActor
public struct TerminalResponder {
    /// Whether the process holds Accessibility trust (`AXIsProcessTrusted`);
    /// without it, reading windows and posting events is impossible → degrade.
    let isTrusted: () -> Bool
    /// Enumerates the open Ghostty windows and their `AXDocument` cwds.
    let listWindows: () -> [TerminalWindow]
    /// Re-reads the live state of the given Ghostty instance (active? key
    /// window's document/title?) right before posting.
    let observeFrontTerminal: (pid_t) -> FrontTerminalObservation?
    /// Posts the keystroke directly to the given pid (`CGEvent.postToPid`).
    let postKeystroke: (AnswerKeystroke, pid_t) -> Void
    /// Waits a beat between delivery-verification attempts (activation is
    /// asynchronous); tests count calls instead of sleeping.
    let settle: () async -> Void
    /// Home directory used to expand a `~` in a window title for the
    /// anti-bare-shell guard.
    let homeDirectory: String
    /// How many times the live target state is (re)checked before giving up.
    let confirmationAttempts: Int

    public init(
        isTrusted: @escaping () -> Bool,
        listWindows: @escaping () -> [TerminalWindow],
        observeFrontTerminal: @escaping (pid_t) -> FrontTerminalObservation?,
        postKeystroke: @escaping (AnswerKeystroke, pid_t) -> Void,
        settle: @escaping () async -> Void,
        homeDirectory: String = NSHomeDirectory(),
        confirmationAttempts: Int = 10
    ) {
        self.isTrusted = isTrusted
        self.listWindows = listWindows
        self.observeFrontTerminal = observeFrontTerminal
        self.postKeystroke = postKeystroke
        self.settle = settle
        self.homeDirectory = homeDirectory
        self.confirmationAttempts = confirmationAttempts
    }

    /// Injects the option's keystroke into the Session's terminal **iff** the
    /// targeting guard reports exactly one Ghostty window at the Session's cwd
    /// (Accessibility trusted), **and** that instance's live state confirms
    /// the delivery right before posting: instance active, key window still at
    /// the Session's cwd, and not a bare-shell tab. Anything else posts
    /// nothing and returns a degrade outcome — a keystroke never lands in a
    /// terminal we are not certain of, and the caller never pretends it did.
    public func inject(optionIndex: Int, forSessionCWD cwd: String?) async -> InjectionOutcome {
        guard isTrusted(), let cwd else { return .uncertainTarget }
        let windows = listWindows()
        guard case let .certain(index) = GhosttyWindowTargeting.verdict(
            forSessionCWD: cwd, amongst: windows.map(\.cwd))
        else { return .uncertainTarget }
        let target = windows[index]
        target.raiseAndActivate()
        for attempt in 0..<max(confirmationAttempts, 1) {
            if attempt > 0 { await settle() }
            guard let front = observeFrontTerminal(target.pid),
                  confirmsDelivery(front, sessionCWD: cwd)
            else { continue }
            postKeystroke(AnswerKeystroke(optionIndex: optionIndex), target.pid)
            return .injected
        }
        return .deliveryUnverified
    }

    /// Whether a live observation proves the keystroke would land in the
    /// Session's terminal: the instance is active (the user sees that Space),
    /// its key window — the visible tab — is still at the Session's cwd, and
    /// that tab is not a bare shell (#81 guard: a Claude Code Session always
    /// rewrites its title, a bare `~/path` title means a plain shell).
    private func confirmsDelivery(
        _ front: FrontTerminalObservation, sessionCWD: String
    ) -> Bool {
        front.isAppActive
            && GhosttyWindowTargeting.normalizedPath(front.keyWindowDocument)
                == GhosttyWindowTargeting.normalizedPath(sessionCWD)
            && !GhosttyWindowTargeting.titleIsBareShellPath(
                front.keyWindowTitle, cwd: sessionCWD, homeDirectory: homeDirectory)
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
        observeFrontTerminal: liveObserveFrontTerminal,
        postKeystroke: livePostKeystroke,
        settle: { try? await Task.sleep(for: .milliseconds(50)) }
    )
}

/// Bundle identifier of the only terminal v1 targets (spike #25). The exact
/// window/tab enumeration below is the shared mechanism **#36 reuses** (focus
/// the exact window, not just the app) instead of growing a second one.
private let ghosttyBundleID = "com.mitchellh.ghostty"

/// Enumerates every window of every running Ghostty instance and reads the cwd
/// each exposes via `AXDocument` (spike #25), paired with its owning pid and
/// its raise action. Iterates **all** instances of the bundle — a second
/// instance (`open -n`) would otherwise hide its windows from a
/// first-instance-only scan.
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
            windows.append(TerminalWindow(cwd: cwd, pid: app.processIdentifier) {
                // Certain target only (the caller vetted unicity): raise the
                // window and activate Ghostty — this shows the user the terminal
                // the answer lands in. Delivery no longer depends on this
                // activation being effective (#81): the keystroke is posted to
                // the pid only after `liveObserveFrontTerminal` confirms it.
                AXUIElementPerformAction(window, kAXRaiseAction as CFString)
                app.activate()
            })
        }
    }
    return windows
}

/// Re-reads the live state of the Ghostty instance right before posting
/// (issue #81): is it the active app, and what document/title does its key
/// window — the visible tab — expose? Read-only AX; the capture showed
/// `AXFocusedWindow` on the app element tracks the visible tab (window-level
/// `AXFocused` stays `false` even on the active app, a Ghostty quirk).
private func liveObserveFrontTerminal(pid: pid_t) -> FrontTerminalObservation? {
    guard let app = NSRunningApplication(processIdentifier: pid) else { return nil }
    let appElement = AXUIElementCreateApplication(pid)
    var window: CFTypeRef?
    guard AXUIElementCopyAttributeValue(
        appElement, kAXFocusedWindowAttribute as CFString, &window) == .success,
        let keyWindow = window
    else { return nil }
    let element = keyWindow as! AXUIElement
    var document: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXDocumentAttribute as CFString, &document)
    var title: CFTypeRef?
    AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title)
    return FrontTerminalObservation(
        isAppActive: app.isActive,
        keyWindowDocument: document as? String,
        keyWindowTitle: title as? String)
}

/// Posts the answer keystroke as `CGEvent`s **to the target pid** (issue #81):
/// the option characters as a unicode string, then Return (virtual key 36)
/// when asked. `postToPid` routes the events into Ghostty's own event queue —
/// its key window, the one just verified — independently of the global key
/// focus, so the keystroke can neither die in the Island panel nor leak to
/// whatever app happens to hold focus (the failure the gate of #77 exposed).
/// The exact sequence is tuned against the live TUI during the HITL FP.
private func livePostKeystroke(_ keystroke: AnswerKeystroke, to pid: pid_t) {
    let source = CGEventSource(stateID: .combinedSessionState)
    let utf16 = Array(keystroke.characters.utf16)
    for keyDown in [true, false] {
        let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
        event?.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        event?.postToPid(pid)
    }
    guard keystroke.sendsReturn else { return }
    let returnKey: CGKeyCode = 36
    CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: true)?
        .postToPid(pid)
    CGEvent(keyboardEventSource: source, virtualKey: returnKey, keyDown: false)?
        .postToPid(pid)
}
