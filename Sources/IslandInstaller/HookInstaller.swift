import Foundation

/// Installs and uninstalls the island hooks in a Claude Code settings.json
/// (ADR-0001: hooks → local server, installed by the app on first launch while
/// preserving existing hooks).
///
/// Merge is strictly additive: existing hook entries are kept entry by entry
/// and the island entry is appended. Idempotence is guaranteed by a marker —
/// the island endpoint URL inside the entry's command.
public struct HookInstaller {
    /// The 7 events island listens to (the server answers 200 to events the
    /// adapter does not know yet, so installing all of them is safe).
    public static let events = [
        "Stop", "SessionStart", "SessionEnd", "UserPromptSubmit",
        "Notification", "PreToolUse", "PostToolUse",
    ]

    /// Marker identifying an island entry, whatever the surrounding command.
    public static let endpoint = "http://127.0.0.1:41414/hooks/claude-code"

    /// Production location of the Claude Code settings file.
    public static var defaultSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
    }

    /// Fire-and-forget hook command: 2 s cap, backgrounded, silent on failure —
    /// Claude Code is never blocked nor slowed down when the app is not running.
    ///
    /// The payload MUST be captured in the foreground before backgrounding
    /// curl: POSIX redirects a background job's stdin to /dev/null in
    /// non-interactive shells, so a plain `curl --data-binary @- … &` would
    /// silently POST an empty body (verified end-to-end, FP #6).
    public static let defaultCommand =
        "payload=$(cat); curl -s --max-time 2 -X POST \"\(endpoint)?token=$(cat ~/.claude/island-token)\" "
        + "-H 'Content-Type: application/json' --data-binary \"$payload\" >/dev/null 2>&1 &"

    private let settingsURL: URL
    private let command: String
    private let now: () -> Date

    public init(
        settingsURL: URL,
        command: String = HookInstaller.defaultCommand,
        now: @escaping () -> Date = Date.init
    ) {
        self.settingsURL = settingsURL
        self.command = command
        self.now = now
    }

    /// Adds the island entry to every event, preserving everything else.
    /// Idempotent: events that already carry an island entry are left alone,
    /// and an unchanged settings file is not rewritten (nor backed up).
    @discardableResult
    public func install() throws -> InstallOutcome {
        var settings = try readSettings()
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for event in Self.events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            guard !entries.contains(where: Self.isIslandEntry) else { continue }
            entries.append(islandEntry)
            hooks[event] = entries
            changed = true
        }

        guard changed else { return .alreadyInstalled }
        settings["hooks"] = hooks
        let backup = try backupExistingFile()
        try write(settings)
        return .installed(backup: backup)
    }

    /// Removes island entries only — every other entry, event and setting is
    /// left exactly as found. Event arrays emptied by the removal lose their
    /// key (island created them), and an emptied hooks section is dropped.
    @discardableResult
    public func uninstall() throws -> UninstallOutcome {
        var settings = try readSettings()
        guard var hooks = settings["hooks"] as? [String: Any] else {
            return .nothingToUninstall
        }
        var changed = false

        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { !Self.isIslandEntry($0) }
            guard kept.count != entries.count else { continue }
            hooks[event] = kept.isEmpty ? nil : kept
            changed = true
        }

        guard changed else { return .nothingToUninstall }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        let backup = try backupExistingFile()
        try write(settings)
        return .uninstalled(backup: backup)
    }

    /// Copies the current settings file, byte for byte, to a timestamped
    /// sibling before it gets rewritten. Returns nil when there is no file yet.
    private func backupExistingFile() throws -> URL? {
        try TimestampedBackup.create(of: settingsURL, at: now())
    }

    /// An entry is island's when one of its commands targets the island endpoint.
    public static func isIslandEntry(_ entry: [String: Any]) -> Bool {
        ((entry["hooks"] as? [[String: Any]]) ?? [])
            .compactMap { $0["command"] as? String }
            .contains { $0.contains(endpoint) }
    }

    private var islandEntry: [String: Any] {
        [
            "matcher": "",
            "hooks": [
                ["type": "command", "command": command, "timeout": 5] as [String: Any]
            ],
        ]
    }

    private func readSettings() throws -> [String: Any] {
        // Only a genuinely absent file means "start fresh": an existing file
        // we cannot read or parse must never be overwritten.
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data),
              let settings = json as? [String: Any]
        else {
            throw InstallerError.unreadableSettings(settingsURL)
        }
        return settings
    }

    private func write(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: settingsURL, options: .atomic)
    }
}

public enum InstallOutcome: Equatable, Sendable {
    /// Hooks were written; `backup` is the pre-write copy of the settings file
    /// (nil when the file did not exist yet).
    case installed(backup: URL?)
    /// Every event already had its island entry — nothing was touched.
    case alreadyInstalled
}

public enum UninstallOutcome: Equatable, Sendable {
    /// Island entries were removed; `backup` is the pre-write copy of the file.
    case uninstalled(backup: URL?)
    /// No island entry found — nothing was touched.
    case nothingToUninstall
}

public enum InstallerError: Error, CustomStringConvertible {
    /// The settings file exists but is not a JSON object: refuse to touch it.
    case unreadableSettings(URL)

    public var description: String {
        switch self {
        case .unreadableSettings(let url):
            return "settings file at \(url.path) is not valid JSON — refusing to modify it"
        }
    }
}
