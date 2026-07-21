import Foundation

/// What clicking "⬆ Mettre à jour vers vY.Z…" concluded (issue #92).
public enum UpdateInstallOutcome: Equatable, Sendable {
    /// The install script was handed off (fire-and-forget: it will quit,
    /// replace and relaunch the app — the process launching it does not
    /// survive to observe the result).
    case launched
    /// A dev build never updates (US15, ADR-0010): it would overwrite itself
    /// with prod. The script is not run.
    case refusedDevBuild
}

/// The one-click update action (issue #92, ADR-0010): hands the actual
/// replacement to `install.sh` — the installer IS the updater, no second
/// write path. Seam pattern of `TerminalResponder.live`: the closures are
/// injected, tests record them, and only `live` touches the real world.
///
/// `currentVersion` must read the REAL app version (`AppVersion.current`),
/// never the `ISLAND_UPDATE_CURRENT_OVERRIDE` seam of #91: the FP can fake
/// the *detection* into offering an update, but the dev guard on the *action*
/// is not bypassable.
public struct UpdateInstaller: Sendable {
    public var currentVersion: @Sendable () -> AppVersion
    public var runInstallScript: @Sendable () -> Void

    public init(
        currentVersion: @escaping @Sendable () -> AppVersion,
        runInstallScript: @escaping @Sendable () -> Void
    ) {
        self.currentVersion = currentVersion
        self.runInstallScript = runInstallScript
    }

    /// The click. No confirmation step (the explicit click IS the consent,
    /// ADR-0010) and no debouncing (the menu item only becomes clickable on
    /// an updateAvailable verdict, and install.sh is idempotent).
    public func install() -> UpdateInstallOutcome {
        guard !currentVersion().isDev else { return .refusedDevBuild }
        runInstallScript()
        return .launched
    }
}

// MARK: - Production seam (Process + install.sh)

extension UpdateInstaller {
    /// URL of the canonical install script (ADR-0010): the update runs the
    /// same script as the Canal d'installation, fetched fresh from `main` so
    /// the updater logic is always the released one.
    static let installScriptURL =
        "https://raw.githubusercontent.com/Taklin1/island/main/scripts/install.sh"

    /// Where the detached script writes its trace — the end-to-end evidence
    /// the HITL gate of #92 reads after the app replaced itself.
    public static let installLogPath = "~/Library/Logs/island-update.log"

    /// Production action backed by `Process`. This is the **only** code that
    /// launches the real script; it is exercised solely by the HITL gate on
    /// the packaged app (version N → N+1 in one click), never by a unit test
    /// and never by the agentic FP (whose bare binary is `-dev`, refused
    /// upstream).
    public static let live = UpdateInstaller(
        currentVersion: { AppVersion.current },
        runInstallScript: liveRunInstallScript
    )
}

/// Launches `install.sh` detached in its own shell, stdout and stderr
/// appended to the log file. The script is downloaded to a temp file first —
/// `curl -f` validates the whole transfer before a single line runs (a bare
/// `curl | bash` would execute a truncated script on a dropped connection).
/// install.sh itself then validates the downloaded bundle BEFORE `pkill`-ing
/// the app (a network failure leaves the running app untouched), replaces
/// `~/Applications/island.app` and relaunches via `open`. The bash child
/// survives the pkill — its command line does not match the
/// "Applications/island.app" pattern the script kills by — and is reparented
/// when the app exits.
private func liveRunInstallScript() {
    let log = NSString(string: UpdateInstaller.installLogPath).expandingTildeInPath
    let script = """
        mkdir -p "$(dirname '\(log)')"
        exec >> '\(log)' 2>&1
        echo "=== island update $(date -u +%Y-%m-%dT%H:%M:%SZ) ==="
        tmp="$(mktemp "${TMPDIR:-/tmp}/island-update-script.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        if curl -fsSL -o "$tmp" '\(UpdateInstaller.installScriptURL)'; then
            bash "$tmp"
        else
            echo "error: could not download install.sh"
        fi
        """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/bash")
    process.arguments = ["-c", script]
    do {
        try process.run()
    } catch {
        // Tolerated-with-trace (LoginItem pattern): the app keeps running,
        // the menu item stays clickable for a retry.
        print("island: update install script failed to launch: \(error)")
    }
}
