import Foundation

/// The safe-targeting guard for answering a blocked Session from the Island
/// (issue #27, ADR-0009, spike #25). Pure logic: given the cwds a set of
/// Ghostty windows expose via the Accessibility `AXDocument` attribute and the
/// cwd of the Session we want to answer, it decides whether exactly one window
/// is *certainly* that Session's terminal.
///
/// The rule is the whole safety of the feature: **a certain target is exactly
/// one matching window**. Zero (no window at that cwd) or several (several
/// Sessions in the same project, splits, background tabs) are *uncertain* — the
/// caller then degrades to Click-to-focus and injects nothing, so a keystroke
/// can never land in the wrong terminal.
///
/// This primitive is deliberately AX-free so it is unit-tested exhaustively and
/// **reused by #36** (focus the exact window, not just the app): both features
/// share this one window/tab mechanism instead of each growing its own.
public enum GhosttyWindowTargeting {
    /// Outcome of matching a Session's cwd against the open Ghostty windows.
    public enum Verdict: Equatable {
        /// Exactly one window matched: its index in the enumerated list. The
        /// caller may raise this window and inject.
        case certain(windowIndex: Int)
        /// Zero or several matches: never inject — degrade to Click-to-focus.
        case uncertain
    }

    /// Verdict for a Session cwd against the cwds the open Ghostty windows
    /// expose (each an `AXDocument` file URL, or `nil` when a window exposed
    /// none). Certain iff exactly one window normalises to the Session's cwd.
    public static func verdict(
        forSessionCWD sessionCWD: String,
        amongst windowDocuments: [String?]
    ) -> Verdict {
        guard let target = normalizedPath(sessionCWD) else { return .uncertain }
        let matches = windowDocuments.indices.filter {
            normalizedPath(windowDocuments[$0]) == target
        }
        return matches.count == 1 ? .certain(windowIndex: matches[0]) : .uncertain
    }

    /// Anti-bare-shell guard (issue #81): whether a window title is exactly
    /// the Session's cwd rendered as a shell prompt path (`~/Documents/island`
    /// or the absolute path) — the signature of a plain shell with no Claude
    /// Code Session in it (a live Session always rewrites its tab title). The
    /// #81 capture showed the visible tab's `AXDocument` can match the cwd
    /// while the Session sits in a hidden tab; refusing bare-shell titles
    /// closes the detectable half of that residual. `nil`/empty titles are not
    /// bare-shell (phantom windows never confirm delivery anyway — no doc).
    public static func titleIsBareShellPath(
        _ title: String?, cwd: String, homeDirectory: String
    ) -> Bool {
        guard var title, !title.isEmpty, let target = normalizedPath(cwd) else { return false }
        if title == "~" { title = homeDirectory }
        if title.hasPrefix("~/") {
            title = homeDirectory + title.dropFirst(1)
        }
        return normalizedPath(title) == target
    }

    /// Canonical filesystem path for either a bare cwd (`Session.cwd`) or an
    /// `AXDocument` file URL (`file:///path/`): strips the `file://` scheme,
    /// percent-decodes, and drops a trailing slash so `"/a/b/"` and `"/a/b"`
    /// compare equal. `nil`/empty in, `nil` out (an empty cwd never matches).
    static func normalizedPath(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        var path = raw
        if let url = URL(string: raw), url.isFileURL {
            // Percent-decoded, scheme-free (handles spaces via %20 etc.).
            path = url.path
        } else if raw.hasPrefix("file://") {
            path = String(raw.dropFirst("file://".count)).removingPercentEncoding
                ?? String(raw.dropFirst("file://".count))
        }
        while path.count > 1, path.hasSuffix("/") { path.removeLast() }
        return path.isEmpty ? nil : path
    }
}
