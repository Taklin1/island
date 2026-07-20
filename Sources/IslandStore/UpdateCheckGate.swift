/// What an update check concluded (issue #91, ADR-0010). `unknown` covers
/// every case where nothing must be shown: dev build, failed fetch, or an
/// uncomparable version — always silent, never an error surface.
public enum UpdateVerdict: Equatable, Sendable {
    /// Nothing to say: dev build (US15), fetch failed (offline, no release
    /// published yet, API down) or an unparseable version. The caller stays
    /// silent apart from its stdout trace.
    case unknown
    /// The installed version is the latest published one (or newer).
    case upToDate
    /// A newer release exists. `version` is the normalized `X.Y.Z` (tag `v`
    /// stripped); `notify` is true only the first time this version is seen —
    /// the caller posts the single macOS notification and *then* persists
    /// `lastNotifiedUpdateVersion` (the write is the caller's effect, never
    /// the gate's).
    case updateAvailable(version: String, notify: Bool)
}

/// The update-detection decision (issue #91): pure over (current version,
/// remote tag, last notified version), pattern of `AnswerFromIslandGate`. No
/// AppKit, no network, no UserDefaults — the caller supplies the inputs
/// (version from `AppVersion`, tag from `UpdateFetcher`, last notified from
/// `AppSettings`) and applies the verdict (menu title, notification).
public enum UpdateCheckGate {
    public static func verdict(
        currentVersion: String,
        latestTag: String?,
        lastNotifiedVersion: String?
    ) -> UpdateVerdict {
        // A dev build never proposes an update (US15, ADR-0010): it would
        // overwrite itself with prod. Short-circuits BEFORE any comparison so
        // no remote tag can ever override it.
        guard !currentVersion.hasSuffix("-dev") else { return .unknown }
        // Failed fetch: silent no-op — offline or no release published is
        // never an error the user sees.
        guard let latestTag else { return .unknown }
        guard let current = semanticVersion(from: currentVersion),
            let remote = semanticVersion(from: latestTag)
        else { return .unknown }
        guard remote > current else { return .upToDate }
        let version = "\(remote.major).\(remote.minor).\(remote.patch)"
        return .updateAvailable(version: version, notify: version != lastNotifiedVersion)
    }

    /// Parses `X.Y.Z` (tag form `vX.Y.Z` accepted) into numeric components.
    /// Numeric, NEVER lexicographic — as strings "0.1.9" > "0.1.24", which
    /// would both miss updates and propose downgrades. Anything else (e.g.
    /// the real tag `v0.1.23-test89` once seen on the repo) is nil: never
    /// propose what cannot be compared.
    private static func semanticVersion(
        from string: String
    ) -> (major: Int, minor: Int, patch: Int)? {
        var body = Substring(string)
        if body.hasPrefix("v") { body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
            let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2]),
            major >= 0, minor >= 0, patch >= 0
        else { return nil }
        return (major, minor, patch)
    }
}
