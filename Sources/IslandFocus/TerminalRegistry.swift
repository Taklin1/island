import Foundation

/// Maps generic terminal identifiers (the `terminal` field of Events) to
/// macOS bundle identifiers. Lives in the Focus module: which terminals exist
/// is neither agent-specific (adapter) nor UI business.
public enum TerminalRegistry {
    /// Terminal used when a Session carries no terminal information.
    public static let defaultTerminal = "ghostty"

    private static let bundleIDs: [String: String] = [
        "ghostty": "com.mitchellh.ghostty"
    ]

    /// Bundle identifier for a terminal identifier, when known.
    public static func bundleID(for terminal: String) -> String? {
        bundleIDs[terminal.lowercased()]
    }

    /// Terminal identifier for a frontmost-app bundle identifier, when it is
    /// a known terminal.
    public static func terminal(forBundleID bundleID: String) -> String? {
        bundleIDs.first(where: { $0.value == bundleID })?.key
    }

    /// Display name used by the launch-by-name fallback.
    public static func appName(for terminal: String) -> String {
        terminal.prefix(1).uppercased() + terminal.dropFirst()
    }
}
