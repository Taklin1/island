import Testing
import IslandStore

/// Exhaustive over the public interface (issue #91, pattern of
/// `AnswerFromIslandGateTests`): newer/equal/older remote, `-dev` guard,
/// failed fetch, notify-once, and the semantic (never lexicographic)
/// comparison.
struct UpdateCheckGateTests {
    @Test("A -dev build never proposes an update, even with a newer remote tag (US15)")
    func devBuildNeverProposes() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24-dev",
            latestTag: "v9.9.9",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .unknown)
    }

    @Test("Failed fetch (offline, no release, API down) is a silent unknown")
    func failedFetchIsUnknown() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: nil,
            lastNotifiedVersion: nil
        )

        #expect(verdict == .unknown)
    }

    @Test("Remote equal to current is up to date")
    func equalRemoteIsUpToDate() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: "v0.1.24",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .upToDate)
    }

    @Test("Remote older than current is up to date — numeric, not lexicographic (0.1.9 < 0.1.24)")
    func olderRemoteIsUpToDate() {
        // Lexicographically "0.1.9" > "0.1.24" would wrongly propose a
        // downgrade; the numeric comparison must say up to date.
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: "v0.1.9",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .upToDate)
    }

    @Test("Remote newer than current proposes the update and notifies the first time")
    func newerRemoteProposesAndNotifies() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: "v0.2.0",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .updateAvailable(version: "0.2.0", notify: true))
    }

    @Test("Semantic comparison: 0.1.9 → v0.1.24 is an update (lexicographic would miss it)")
    func semanticComparisonNotLexicographic() {
        // Lexicographically "0.1.24" < "0.1.9" would wrongly say up to date.
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.9",
            latestTag: "v0.1.24",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .updateAvailable(version: "0.1.24", notify: true))
    }

    @Test("Major and minor components outrank patch")
    func majorAndMinorOutrankPatch() {
        #expect(UpdateCheckGate.verdict(
            currentVersion: "0.9.9", latestTag: "v1.0.0", lastNotifiedVersion: nil)
            == .updateAvailable(version: "1.0.0", notify: true))
        #expect(UpdateCheckGate.verdict(
            currentVersion: "1.0.0", latestTag: "v0.9.9", lastNotifiedVersion: nil)
            == .upToDate)
    }

    @Test("Already-notified version proposes again but never re-notifies")
    func alreadyNotifiedVersionDoesNotReNotify() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: "v0.2.0",
            lastNotifiedVersion: "0.2.0"
        )

        #expect(verdict == .updateAvailable(version: "0.2.0", notify: false))
    }

    @Test("A version newer than the last notified one notifies once more")
    func newerVersionThanLastNotifiedNotifiesAgain() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: "v0.3.0",
            lastNotifiedVersion: "0.2.0"
        )

        #expect(verdict == .updateAvailable(version: "0.3.0", notify: true))
    }

    @Test("A tag without the v prefix still parses")
    func tagWithoutVPrefixParses() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: "0.2.0",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .updateAvailable(version: "0.2.0", notify: true))
    }

    @Test("A non-semver remote tag is unknown — real tag v0.1.23-test89 seen on the repo")
    func nonSemverRemoteTagIsUnknown() {
        // Real case: the temporary FP #89 test release was tagged
        // v0.1.23-test89 (captured 2026-07-20). Never propose what cannot be
        // compared.
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "0.1.24",
            latestTag: "v0.1.23-test89",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .unknown)
    }

    @Test("A non-semver current version is unknown")
    func nonSemverCurrentVersionIsUnknown() {
        let verdict = UpdateCheckGate.verdict(
            currentVersion: "garbage",
            latestTag: "v0.2.0",
            lastNotifiedVersion: nil
        )

        #expect(verdict == .unknown)
    }
}
