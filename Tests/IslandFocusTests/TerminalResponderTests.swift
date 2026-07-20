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

/// The end-to-end targeting-and-injection decision of issue #27, driven through
/// injectable seams so the real Accessibility/CGEvent posting — the part the
/// spike proved must NEVER run against the live Ghostty — is exercised only by
/// the HITL FP, never here. These tests pin the decision: inject on a certain
/// target, degrade (post nothing) on anything uncertain.
@MainActor
struct TerminalResponderTests {
    /// A recording double for the OS side-effects, so a test asserts *what
    /// would be done* without touching a real terminal.
    final class Recorder {
        var raisedWindowCWDs: [String?] = []
        var posted: [AnswerKeystroke] = []
    }

    private func responder(
        windows: [String?],
        trusted: Bool,
        recorder: Recorder
    ) -> TerminalResponder {
        TerminalResponder(
            isTrusted: { trusted },
            listWindows: {
                windows.map { cwd in
                    TerminalWindow(cwd: cwd) { recorder.raisedWindowCWDs.append(cwd) }
                }
            },
            postKeystroke: { recorder.posted.append($0) }
        )
    }

    @Test("Certain target: raises that window and injects the option keystroke")
    func certainTargetInjects() {
        let recorder = Recorder()
        let responder = responder(
            windows: ["file:///Users/loic/Documents/island/",
                      "file:///Users/loic/Documents/akutia/"],
            trusted: true,
            recorder: recorder)

        let injected = responder.inject(
            optionIndex: 1, forSessionCWD: "/Users/loic/Documents/island")

        #expect(injected)
        // Raised the sole matching window, not the other project's.
        #expect(recorder.raisedWindowCWDs == ["file:///Users/loic/Documents/island/"])
        #expect(recorder.posted == [AnswerKeystroke(optionIndex: 1)])
    }

    @Test("Uncertain target (several windows): injects nothing, degrades")
    func uncertainTargetDegrades() {
        let recorder = Recorder()
        let responder = responder(
            windows: ["file:///Users/loic/Documents/akutia/",
                      "file:///Users/loic/Documents/akutia/"],
            trusted: true,
            recorder: recorder)

        let injected = responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/akutia")

        #expect(!injected)
        #expect(recorder.raisedWindowCWDs.isEmpty)
        #expect(recorder.posted.isEmpty)
    }

    @Test("No matching window: injects nothing, degrades")
    func noMatchDegrades() {
        let recorder = Recorder()
        let responder = responder(
            windows: ["file:///Users/loic/Documents/other/"],
            trusted: true,
            recorder: recorder)

        #expect(!responder.inject(optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island"))
        #expect(recorder.posted.isEmpty)
    }

    @Test("Without Accessibility trust: never even reads windows, degrades")
    func untrustedDegrades() {
        let recorder = Recorder()
        var listed = false
        let responder = TerminalResponder(
            isTrusted: { false },
            listWindows: { listed = true; return [] },
            postKeystroke: { recorder.posted.append($0) })

        let injected = responder.inject(
            optionIndex: 0, forSessionCWD: "/Users/loic/Documents/island")

        #expect(!injected)
        #expect(!listed) // no AX read at all when untrusted
        #expect(recorder.posted.isEmpty)
    }

    @Test("Unknown Session cwd: injects nothing, degrades")
    func unknownCWDDegrades() {
        let recorder = Recorder()
        let responder = responder(
            windows: ["file:///Users/loic/Documents/island/"],
            trusted: true,
            recorder: recorder)

        #expect(!responder.inject(optionIndex: 0, forSessionCWD: nil))
        #expect(recorder.posted.isEmpty)
    }
}
