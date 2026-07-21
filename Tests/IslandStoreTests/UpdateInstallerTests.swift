import Testing

@testable import IslandStore

/// Wiring tests for the one-click update action (issue #92, ADR-0010): the
/// click must hand off to the install-script closure exactly once — and never
/// on a dev build, whatever the FP seams fed the *detection* gate. The live
/// closure (Process + install.sh) is never run here; the real replacement is
/// proven at the HITL gate on the packaged app.
struct UpdateInstallerTests {

    // Single-threaded test recorder behind the @Sendable seam (the
    // LocalServer `@unchecked Sendable` precedent).
    private final class Recorder: @unchecked Sendable {
        var runCount = 0
    }

    private func installer(
        version: String?, recorder: Recorder
    ) -> UpdateInstaller {
        UpdateInstaller(
            currentVersion: { AppVersion(bundleShortVersion: version) },
            runInstallScript: { recorder.runCount += 1 }
        )
    }

    @Test func releaseBuildLaunchesTheInstallScriptOnce() {
        let recorder = Recorder()
        let outcome = installer(version: "0.1.27", recorder: recorder).install()
        #expect(outcome == .launched)
        #expect(recorder.runCount == 1)
    }

    @Test func devBuildNeverRunsTheInstallScript() {
        let recorder = Recorder()
        let outcome = installer(version: "0.1.27-dev", recorder: recorder).install()
        #expect(outcome == .refusedDevBuild)
        #expect(recorder.runCount == 0)
    }

    @Test func bareBinaryWithoutBundleVersionIsRefusedAsDev() {
        // The bare SwiftPM binary (what the agentic FP drives) has no
        // Info.plist: AppVersion falls back to "0.0.0-dev" and the click must
        // refuse — this is the runtime path the FP asserts through traces.
        let recorder = Recorder()
        let outcome = installer(version: nil, recorder: recorder).install()
        #expect(outcome == .refusedDevBuild)
        #expect(recorder.runCount == 0)
    }

    @Test func eachInstallCallRunsTheScriptAgain() {
        // No debouncing in the action itself: the menu item is the gate (it
        // only becomes clickable on an updateAvailable verdict), and install.sh
        // is idempotent by design — a second click is a legitimate re-run.
        let recorder = Recorder()
        let installer = installer(version: "0.1.27", recorder: recorder)
        _ = installer.install()
        _ = installer.install()
        #expect(recorder.runCount == 2)
    }
}
