import Testing
@testable import IslandFocus

/// The safe-targeting guard of issue #27 (ADR-0009, spike #25): a Session's
/// Ghostty window is a *certain* target only when **exactly one** window
/// exposes an `AXDocument` matching the Session's cwd. Zero or several matches
/// are *uncertain* → the caller degrades to Click-to-focus, never a keystroke
/// in the wrong terminal. Pure logic over simulated windows — the real AX read
/// is exercised by the HITL injection FP, never here.
struct GhosttyWindowTargetingTests {
    @Test("Exactly one window at the Session's cwd is a certain target")
    func soleMatchIsCertain() {
        // The spike's real capture: 8 windows across 3 projects. Only `island`
        // has a single window → the only certain target.
        let windows = [
            "file:///Users/loic/Documents/island/",
            "file:///Users/loic/Documents/akutia/",
            "file:///Users/loic/Documents/akutia/",
            "file:///Users/loic/Documents/akutia/",
            "file:///Users/loic/Documents/akutia/",
            "file:///Users/loic/Documents/hedgencia/",
            "file:///Users/loic/Documents/hedgencia/",
            "file:///Users/loic/Documents/hedgencia/",
        ]

        let verdict = GhosttyWindowTargeting.verdict(
            forSessionCWD: "/Users/loic/Documents/island",
            amongst: windows)

        #expect(verdict == .certain(windowIndex: 0))
    }

    @Test("Several windows at the same cwd are uncertain — never inject")
    func severalMatchesAreUncertain() {
        // The spike's `akutia` case: 4 windows in one project → ambiguous, so
        // the answer must degrade to focus rather than pick one at random.
        let windows = Array(repeating: "file:///Users/loic/Documents/akutia/", count: 4)

        #expect(GhosttyWindowTargeting.verdict(
            forSessionCWD: "/Users/loic/Documents/akutia",
            amongst: windows) == .uncertain)
    }

    @Test("No window at the Session's cwd is uncertain — never inject")
    func noMatchIsUncertain() {
        let windows = ["file:///Users/loic/Documents/other/"]

        #expect(GhosttyWindowTargeting.verdict(
            forSessionCWD: "/Users/loic/Documents/island",
            amongst: windows) == .uncertain)
        // No window at all is uncertain too.
        #expect(GhosttyWindowTargeting.verdict(
            forSessionCWD: "/Users/loic/Documents/island",
            amongst: []) == .uncertain)
    }

    @Test("A trailing slash and file:// scheme never break the match")
    func normalisationToleratesSchemeAndTrailingSlash() {
        // AXDocument is `file:///path/`; Session.cwd is a bare `/path`. They
        // must still compare equal, and a percent-encoded space too.
        #expect(GhosttyWindowTargeting.verdict(
            forSessionCWD: "/Users/loic/My Project",
            amongst: ["file:///Users/loic/My%20Project/"]) == .certain(windowIndex: 0))
    }

    @Test("A window exposing no AXDocument (nil) never matches")
    func windowWithoutDocumentNeverMatches() {
        // A split/background surface may expose no cwd: it is simply not counted,
        // and the sole real match stays certain.
        let windows: [String?] = [nil, "file:///Users/loic/Documents/island/"]

        #expect(GhosttyWindowTargeting.verdict(
            forSessionCWD: "/Users/loic/Documents/island",
            amongst: windows) == .certain(windowIndex: 1))
    }

    @Test("An empty Session cwd is uncertain — a missing cwd never targets")
    func emptySessionCWDIsUncertain() {
        #expect(GhosttyWindowTargeting.verdict(
            forSessionCWD: "",
            amongst: ["file:///Users/loic/Documents/island/"]) == .uncertain)
    }
}

/// The anti-bare-shell guard of issue #81: a visible tab whose title is just
/// the prompt path is a plain shell, not a Claude Code Session (a live Session
/// always rewrites its tab title) — delivery must refuse it even though its
/// `AXDocument` matches the Session's cwd.
struct BareShellTitleTests {
    @Test("A title that is the cwd as a ~-path or absolute path is a bare shell")
    func promptPathTitlesAreBareShell() {
        #expect(GhosttyWindowTargeting.titleIsBareShellPath(
            "~/Documents/island", cwd: "/Users/loic/Documents/island",
            homeDirectory: "/Users/loic"))
        #expect(GhosttyWindowTargeting.titleIsBareShellPath(
            "/Users/loic/Documents/island", cwd: "/Users/loic/Documents/island",
            homeDirectory: "/Users/loic"))
        // The home directory itself, as Ghostty renders it.
        #expect(GhosttyWindowTargeting.titleIsBareShellPath(
            "~", cwd: "/Users/loic", homeDirectory: "/Users/loic"))
    }

    @Test("A Claude Code task title is not a bare shell — delivery may proceed")
    func taskTitlesAreNotBareShell() {
        for title in ["✳ Claude Code", "⠐ Implémenter la livraison fiable (#81)", "👻"] {
            #expect(!GhosttyWindowTargeting.titleIsBareShellPath(
                title, cwd: "/Users/loic/Documents/island", homeDirectory: "/Users/loic"))
        }
    }

    @Test("A missing or empty title is not treated as a bare shell")
    func missingTitleIsNotBareShell() {
        // A nil/empty title alone never blocks: phantom windows expose no
        // document either, so delivery verification already refuses them.
        #expect(!GhosttyWindowTargeting.titleIsBareShellPath(
            nil, cwd: "/Users/loic/Documents/island", homeDirectory: "/Users/loic"))
        #expect(!GhosttyWindowTargeting.titleIsBareShellPath(
            "", cwd: "/Users/loic/Documents/island", homeDirectory: "/Users/loic"))
    }

    @Test("A different project path in the title is not this Session's bare shell")
    func otherPathIsNotBareShell() {
        #expect(!GhosttyWindowTargeting.titleIsBareShellPath(
            "~/Documents/akutia", cwd: "/Users/loic/Documents/island",
            homeDirectory: "/Users/loic"))
    }
}
