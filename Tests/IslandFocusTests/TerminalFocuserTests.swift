import Testing
import IslandFocus
import IslandStore

@MainActor
struct TerminalFocuserTests {
    @Test("Focusing a ghostty Session activates the Ghostty bundle")
    func focusActivatesGhosttyBundle() {
        var activated: [String] = []
        var launched: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { activated.append($0); return true },
            launchApplication: { launched.append($0) }
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
            launchApplication: { _ in }
        )

        focuser.focus(terminal: nil)

        #expect(activated == ["com.mitchellh.ghostty"])
    }

    @Test("Activation failure falls back to launching the app by name")
    func activationFailureLaunchesByName() {
        var launched: [String] = []
        let focuser = TerminalFocuser(
            activateBundleID: { _ in false },
            launchApplication: { launched.append($0) }
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
