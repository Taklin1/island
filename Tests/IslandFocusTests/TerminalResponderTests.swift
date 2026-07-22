import Foundation
import Testing
@testable import IslandFocus

/// The answer keystroke built for an AskUserQuestion option (issue #27). The
/// physical selector sequence in the Claude Code TUI is confirmed on the live
/// TUI during the HITL injection FP; this only pins the v1-frozen mapping so a
/// later tuning stays isolated from the targeting guard.
struct AnswerKeystrokeTests {
    @Test("The keystroke for an option is its 1-based number, then Return")
    func keystrokeIsOneBasedNumberThenReturn() {
        // The card shows options as 1/2/3…; the injected key matches what the
        // user sees. Index 0 → "1", index 2 → "3".
        #expect(AnswerKeystroke(optionIndex: 0).characters == "1")
        #expect(AnswerKeystroke(optionIndex: 2).characters == "3")
        // Return confirms the highlighted choice (v1 assumption, HITL-tuned).
        #expect(AnswerKeystroke(optionIndex: 0).sendsReturn)
    }
}

/// The end-to-end targeting-and-delivery decision of issues #27/#81, driven
/// through injectable seams so the real Accessibility/CGEvent posting — the
/// part the spike proved must NEVER run against the live Ghostty — is
/// exercised only by the HITL FP, never here. These tests pin the decision:
/// post only to a target *verified at the instant of delivery* (issue #81 —
/// the capture proved a "certain" verdict alone does not mean the keystroke
/// arrives), and degrade truthfully on anything else.
@MainActor
struct TerminalResponderTests {
    /// A recording double for the OS side-effects, so a test asserts *what
    /// would be done* without touching a real terminal.
    final class Recorder {
        var raisedWindowCWDs: [String?] = []
        var posted: [(keystroke: AnswerKeystroke, pid: pid_t)] = []
        var settleCount = 0
    }

    private func responder(
        windows: [(cwd: String?, pid: pid_t)],
        trusted: Bool = true,
        observations: [FrontTerminalObservation?],
        recorder: Recorder
    ) -> TerminalResponder {
        var remaining = observations
        return TerminalResponder(
            isTrusted: { trusted },
            listWindows: {
                windows.map { window in
                    TerminalWindow(cwd: window.cwd, pid: window.pid) {
                        recorder.raisedWindowCWDs.append(window.cwd)
                    }
                }
            },
            observeFrontTerminal: { _ in
                remaining.isEmpty ? nil : remaining.removeFirst()
            },
            postKeystroke: { keystroke, pid in
                recorder.posted.append((keystroke, pid))
            },
            settle: { recorder.settleCount += 1 },
            homeDirectory: "/Users/loic"
        )
    }

    @Test("Certain and verified target: raises it and posts the keystroke to its pid")
    func verifiedTargetInjects() async {
        let recorder = Recorder()
        let responder = responder(
            windows: [("file:///Users/loic/Documents/island/", 3488),
                      ("file:///Users/loic/Documents/akutia/", 3488)],
            observations: [FrontTerminalObservation(
                isAppActive: true,
                keyWindowDocument: "file:///Users/loic/Documents/island/",
                keyWindowTitle: "✳ Claude Code")],
            recorder: recorder)

        let outcome = await responder.inject(
            optionIndex: 1, forSessionCWD: "/Users/loic/Documents/island")

        #expect(outcome == .injected)
        // Raised the sole matching window, not the other project's.
        #expect(recorder.raisedWindowCWDs == ["file:///Users/loic/Documents/island/"])
        // Posted the option keystroke directly to that window's pid (#81:
        // pid-routed delivery — the keystroke can never leak to another app).
        #expect(recorder.posted.map { $0.keystroke } == [AnswerKeystroke(optionIndex: 1)])
        #expect(recorder.posted.map { $0.pid } == [3488])
    }

    @Test("Activation race (#81): waits for the terminal to confirm, then posts")
    func activationRaceSettlesThenInjects() async {
        let recorder = Recorder()
        // First observation: Ghostty not yet active (the Island panel click
        // held focus an instant — the bug of #81). Second: confirmed.
        let responder = responder(
            windows: [("file:///Users/loic/Documents/island/", 42)],
            observations: [
                FrontTerminalObservation(
                    isAppActive: false,
                    keyWindowDocument: "file:///Users/loic/Documents/island/",
                    keyWindowTitle: "✳ Claude Code"),
                FrontTerminalObservation(
                    isAppActive: true,
                    keyWindowDocument: "file:///Users/loic/Documents/island/",
                    keyWindowTitle: "✳ Claude Code"),
            ],
            recorder: recorder)

        let outcome = await responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island")

        #expect(outcome == .injected)
        // One settle beat between the failed and the confirmed observation,
        // and exactly one keystroke posted.
        #expect(recorder.settleCount == 1)
        #expect(recorder.posted.map { $0.pid } == [42])
    }

    @Test("Delivery never verified (#81): posts nothing and says so — no lie")
    func unverifiedDeliveryPostsNothing() async {
        let recorder = Recorder()
        // The terminal never becomes active within the delivery budget (e.g.
        // the panel kept focus, or the user switched Space mid-flight).
        let stuck = FrontTerminalObservation(
            isAppActive: false,
            keyWindowDocument: "file:///Users/loic/Documents/island/",
            keyWindowTitle: "✳ Claude Code")
        let responder = responder(
            windows: [("file:///Users/loic/Documents/island/", 42)],
            observations: Array(repeating: stuck, count: 20),
            recorder: recorder)

        let outcome = await responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island")

        // Truthful outcome: the caller degrades to focus, the card never
        // shows "working" for a keystroke that did not go out.
        #expect(outcome == .deliveryUnverified)
        #expect(recorder.posted.isEmpty)
    }

    @Test("Visible tab moved off the Session's cwd (#81): refuses to post")
    func visibleTabAtOtherCwdRefuses() async {
        let recorder = Recorder()
        // Between the verdict and the post, the visible tab changed to another
        // project — posting would land in the wrong terminal.
        let moved = FrontTerminalObservation(
            isAppActive: true,
            keyWindowDocument: "file:///Users/loic/Documents/akutia/",
            keyWindowTitle: "✳ Other task")
        let responder = responder(
            windows: [("file:///Users/loic/Documents/island/", 42)],
            observations: Array(repeating: moved, count: 20),
            recorder: recorder)

        let outcome = await responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island")

        #expect(outcome == .deliveryUnverified)
        #expect(recorder.posted.isEmpty)
    }

    @Test("Bare-shell visible tab (#81): same cwd but no Session in it — refuses")
    func bareShellTabRefuses() async {
        let recorder = Recorder()
        // The visible tab is at the Session's cwd but titled as a bare prompt
        // path — the capture's signature of a plain shell (the Session sits in
        // a hidden tab). Typing "1⏎" into a shell is a wrong-target delivery.
        let bareShell = FrontTerminalObservation(
            isAppActive: true,
            keyWindowDocument: "file:///Users/loic/Documents/island/",
            keyWindowTitle: "~/Documents/island")
        let responder = responder(
            windows: [("file:///Users/loic/Documents/island/", 42)],
            observations: Array(repeating: bareShell, count: 20),
            recorder: recorder)

        let outcome = await responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island")

        #expect(outcome == .deliveryUnverified)
        #expect(recorder.posted.isEmpty)
    }

    @Test("Uncertain target (several windows): posts nothing, degrades")
    func uncertainTargetDegrades() async {
        let recorder = Recorder()
        let responder = responder(
            windows: [("file:///Users/loic/Documents/akutia/", 1),
                      ("file:///Users/loic/Documents/akutia/", 1)],
            observations: [],
            recorder: recorder)

        let outcome = await responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/akutia")

        #expect(outcome == .uncertainTarget)
        #expect(recorder.raisedWindowCWDs.isEmpty)
        #expect(recorder.posted.isEmpty)
    }

    @Test("No matching window: posts nothing, degrades")
    func noMatchDegrades() async {
        let recorder = Recorder()
        let responder = responder(
            windows: [("file:///Users/loic/Documents/other/", 1)],
            observations: [],
            recorder: recorder)

        let outcome = await responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island")

        #expect(outcome == .uncertainTarget)
        #expect(recorder.posted.isEmpty)
    }

    @Test("Without Accessibility trust: never even reads windows, degrades")
    func untrustedDegrades() async {
        let recorder = Recorder()
        var listed = false
        let responder = TerminalResponder(
            isTrusted: { false },
            listWindows: { listed = true; return [] },
            observeFrontTerminal: { _ in Optional<FrontTerminalObservation>.none },
            postKeystroke: { keystroke, pid in recorder.posted.append((keystroke, pid)) },
            settle: {},
            homeDirectory: "/Users/loic")

        let outcome = await responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island")

        #expect(outcome == .uncertainTarget)
        #expect(!listed) // no AX read at all when untrusted
        #expect(recorder.posted.isEmpty)
    }

    @Test("Unknown Session cwd: posts nothing, degrades")
    func unknownCWDDegrades() async {
        let recorder = Recorder()
        let responder = responder(
            windows: [("file:///Users/loic/Documents/island/", 1)],
            observations: [],
            recorder: recorder)

        #expect(await responder.inject(optionIndex: 0, forSessionCWD: nil) == .uncertainTarget)
        #expect(recorder.posted.isEmpty)
    }
}
