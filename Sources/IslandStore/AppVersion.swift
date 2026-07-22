import Foundation

/// The version island itself runs (issue #88, ADR-0010): the single source the
/// launch trace and the menu-bar item both read, and the ground for the "a
/// `-dev` build never updates" guard (US15). Pure over the string read from the
/// bundle — the caller supplies it, so tests never depend on the real
/// `Bundle.main` (which has no Info.plist for the bare SwiftPM binary).
public struct AppVersion: Equatable, Sendable {
    /// The raw version string, e.g. `"0.1.24-dev"` or `"0.1.24"`. Callers add
    /// their own prefix (trace: `island: version …`, menu: `island v…`).
    public let value: String
    /// True for a local/dev build (packaged with the `-dev` suffix, or running
    /// as the bare SwiftPM binary). A dev build never proposes an update.
    public let isDev: Bool

    public init(bundleShortVersion: String?) {
        // Bare SwiftPM binary: no Info.plist, so no version string. Fall back
        // to a readable value marked dev — never a fatalError, never an empty
        // string, and a bare binary is never a release (US15).
        if let bundleShortVersion, !bundleShortVersion.isEmpty {
            self.value = bundleShortVersion
        } else {
            self.value = "0.0.0-dev"
        }
        self.isDev = self.value.hasSuffix("-dev")
    }

    /// The version of the running app, read from `Bundle.main` (the Info.plist
    /// written by `scripts/package_app.sh`). Live seam — tests never call it,
    /// they exercise `init(bundleShortVersion:)` directly.
    public static var current: AppVersion {
        AppVersion(
            bundleShortVersion:
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String)
    }
}
