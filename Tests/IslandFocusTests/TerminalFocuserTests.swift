import Testing
import IslandFocus
import IslandStore

@MainActor
struct TerminalFocuserTests {
    @Test("Certain target: raises the Session's exact window, not just the app")
    func certainTargetRaisesExactWindow() {
        var raised: [String] = []
        var activated: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { activated.append($0); return true },
            launchApplication: { _ in },
            isTrusted: { true },
            listWindows: {
                [TerminalWindow(cwd: "file:///Users/loic/Documents/island/") {
                    raised.append("island")
                 },
                 TerminalWindow(cwd: "file:///Users/loic/Documents/akutia/") {
                    raised.append("akutia")
                 }]
            }
        )

        let outcome = focuser.focus(terminal: "ghostty", cwd: "/Users/loic/Documents/island")

        #expect(raised == ["island"])
        #expect(activated.isEmpty)
        // The caller traces the outcome so the agentic FP can observe which
        // path the click took without inspecting pixels.
        #expect(outcome == .exactWindow)
    }

    @Test("Uncertain target (zero or several windows at the cwd): activates the whole app")
    func uncertainTargetActivatesApp() {
        var raised: [String] = []
        var activated: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { activated.append($0); return true },
            launchApplication: { _ in },
            isTrusted: { true },
            listWindows: {
                [TerminalWindow(cwd: "file:///Users/loic/Documents/island/") {
                    raised.append("island-1")
                 },
                 TerminalWindow(cwd: "file:///Users/loic/Documents/island/") {
                    raised.append("island-2")
                 }]
            }
        )

        // Two windows at the Session's cwd (splits, second instance)…
        let two = focuser.focus(terminal: "ghostty", cwd: "/Users/loic/Documents/island")
        // …and zero windows at it (other Space, hidden tab — capture #81).
        let zero = focuser.focus(terminal: "ghostty", cwd: "/Users/loic/Documents/elsewhere")

        #expect(raised.isEmpty)
        #expect(activated == ["com.mitchellh.ghostty", "com.mitchellh.ghostty"])
        #expect(two == .app)
        #expect(zero == .app)
    }

    @Test("Without Accessibility trust: the app is activated immediately, windows never read")
    func withoutTrustActivatesAppWithoutEnumerating() {
        var enumerated = false
        var activated: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { activated.append($0); return true },
            launchApplication: { _ in },
            isTrusted: { false },
            listWindows: { enumerated = true; return [] }
        )

        focuser.focus(terminal: "ghostty", cwd: "/Users/loic/Documents/island")

        #expect(!enumerated)
        #expect(activated == ["com.mitchellh.ghostty"])
    }

    @Test("Non-Ghostty terminal stays app-level even with trust and a cwd")
    func nonGhosttyTerminalStaysAppLevel() {
        var enumerated = false
        var launched: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { _ in false },
            launchApplication: { launched.append($0) },
            isTrusted: { true },
            listWindows: { enumerated = true; return [] }
        )

        focuser.focus(terminal: "iterm", cwd: "/Users/loic/Documents/island")

        #expect(!enumerated)
        #expect(launched == ["Iterm"])
    }

    @Test("Unknown Session cwd: the app is activated, windows never read")
    func unknownCWDActivatesApp() {
        var enumerated = false
        var activated: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { activated.append($0); return true },
            launchApplication: { _ in },
            isTrusted: { true },
            listWindows: { enumerated = true; return [] }
        )

        focuser.focus(terminal: "ghostty", cwd: nil)

        #expect(!enumerated)
        #expect(activated == ["com.mitchellh.ghostty"])
    }

    @Test("Focusing a ghostty Session activates the Ghostty bundle")
    func focusActivatesGhosttyBundle() {
        var activated: [String] = []
        var launched: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { activated.append($0); return true },
            launchApplication: { launched.append($0) },
            isTrusted: { false },
            listWindows: { [] }
        )

        focuser.focus(terminal: "ghostty")

        #expect(activated == ["com.mitchellh.ghostty"])
        #expect(launched.isEmpty)
    }

    @Test("Unknown terminal on the Event: falls back to the default (ghostty)")
    func nilTerminalFallsBackToDefault() {
        var activated: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { activated.append($0); return true },
            launchApplication: { _ in },
            isTrusted: { false },
            listWindows: { [] }
        )

        focuser.focus(terminal: nil)

        #expect(activated == ["com.mitchellh.ghostty"])
    }

    @Test("Activation failure falls back to launching the app by name")
    func activationFailureLaunchesByName() {
        var launched: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { _ in false },
            launchApplication: { launched.append($0) },
            isTrusted: { false },
            listWindows: { [] }
        )

        focuser.focus(terminal: "ghostty")

        #expect(launched == ["Ghostty"])
    }
}

@MainActor
struct TerminalFocusAcknowledgerTests {
    @Test("Focusing the terminal of a pending Session acknowledges it; other apps do not")
    func terminalFocusAcknowledges() {
        let store = SessionStore()
        store.apply(AgentEvent(
            sessionID: "s1", kind: .waitingForUser(message: nil),
            terminal: "ghostty", agent: "claude-code"
        ))
        let acknowledger = TerminalFocusAcknowledger(store: store)

        acknowledger.handleActivation(bundleID: "com.apple.Safari")
        #expect(store.sessions[0].needsAcknowledgement)

        acknowledger.handleActivation(bundleID: "com.mitchellh.ghostty")
        #expect(!store.sessions[0].needsAcknowledgement)
    }
}
