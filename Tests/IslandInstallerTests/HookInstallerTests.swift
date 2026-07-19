import Foundation
import Testing
import IslandInstaller

/// Installer seam (issue #6): fixtures on disk in, resulting settings.json out.
/// All tests operate on temporary fixture files — never on the real
/// ~/.claude/settings.json.
struct HookInstallerTests {
    /// Mirrors the real-world case: third-party hooks (pixel-agents) already
    /// registered on the same events island uses, plus unrelated top-level keys.
    static let thirdPartyFixture = """
    {
      "model": "fable",
      "permissions": { "allow": ["WebSearch"], "deny": [] },
      "hooks": {
        "Stop": [
          {
            "matcher": "",
            "hooks": [
              { "type": "command", "command": "node \\"/Users/loic/.pixel-agents/hooks/claude-hook.js\\"", "timeout": 5 }
            ]
          }
        ],
        "SessionStart": [
          {
            "matcher": "",
            "hooks": [
              { "type": "command", "command": "node \\"/Users/loic/.pixel-agents/hooks/claude-hook.js\\"", "timeout": 5 }
            ]
          }
        ],
        "SubagentStop": [
          {
            "matcher": "",
            "hooks": [
              { "type": "command", "command": "node \\"/Users/loic/.pixel-agents/hooks/claude-hook.js\\"", "timeout": 5 }
            ]
          }
        ]
      }
    }
    """

    @Test("Installing over third-party hooks appends island entries without losing anything")
    func installPreservesThirdPartyHooks() throws {
        let fixture = try SettingsFixture(contents: Self.thirdPartyFixture)
        let installer = HookInstaller(settingsURL: fixture.url)

        try installer.install()

        let settings = try fixture.readJSON()
        let hooks = try #require(settings["hooks"] as? [String: Any])

        // Island hooks are present on all 7 events.
        for event in HookInstaller.events {
            let entries = try #require(hooks[event] as? [[String: Any]], "missing \(event)")
            #expect(entries.contains(where: Self.isIslandEntry), "no island entry on \(event)")
        }

        // Every pre-existing third-party entry is still there, entry by entry.
        for event in ["Stop", "SessionStart", "SubagentStop"] {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.contains(where: Self.isPixelAgentsEntry), "lost third-party entry on \(event)")
        }
        // Events island does not touch keep exactly their original entries.
        #expect((hooks["SubagentStop"] as? [[String: Any]])?.count == 1)

        // Unrelated top-level keys survive.
        #expect(settings["model"] as? String == "fable")
        #expect((settings["permissions"] as? [String: Any]) != nil)
    }

    @Test("Reinstalling is idempotent: no duplicate entries, file untouched")
    func reinstallIsIdempotent() throws {
        let fixture = try SettingsFixture(contents: Self.thirdPartyFixture)
        let installer = HookInstaller(settingsURL: fixture.url)

        try installer.install()
        let afterFirst = try fixture.rawBytes()
        try installer.install()

        #expect(try fixture.rawBytes() == afterFirst)
        let hooks = try #require(try fixture.readJSON()["hooks"] as? [String: Any])
        for event in HookInstaller.events {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.filter(Self.isIslandEntry).count == 1, "duplicate island entry on \(event)")
        }
    }

    @Test("A timestamped backup with the original bytes is written before any change")
    func backupIsWrittenBeforeAnyChange() throws {
        let fixture = try SettingsFixture(contents: Self.thirdPartyFixture)
        let original = try fixture.rawBytes()
        let installer = HookInstaller(settingsURL: fixture.url)

        let outcome = try installer.install()

        guard case .installed(let backup) = outcome, let backup else {
            Issue.record("expected .installed with a backup, got \(outcome)")
            return
        }
        #expect(try Data(contentsOf: backup) == original)
        #expect(backup.lastPathComponent.hasPrefix("settings.json.island-backup-"))

        // A no-op reinstall must not pile up backups.
        #expect(try installer.install() == .alreadyInstalled)
        let backups = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
            .filter { $0.contains("island-backup") }
        #expect(backups.count == 1)
    }

    @Test("Uninstalling removes only island entries and restores the initial settings")
    func uninstallRestoresInitialState() throws {
        let fixture = try SettingsFixture(contents: Self.thirdPartyFixture)
        let installer = HookInstaller(settingsURL: fixture.url)
        try installer.install()

        let outcome = try installer.uninstall()

        guard case .uninstalled(let backup) = outcome else {
            Issue.record("expected .uninstalled, got \(outcome)")
            return
        }
        #expect(backup != nil, "uninstall rewrites the file, so it must back it up first")
        let restored = try fixture.readJSON()
        let original = try #require(
            try JSONSerialization.jsonObject(
                with: Data(Self.thirdPartyFixture.utf8)) as? [String: Any]
        )
        #expect(NSDictionary(dictionary: restored) == NSDictionary(dictionary: original))

        // Uninstalling again is a no-op.
        #expect(try installer.uninstall() == .nothingToUninstall)
    }

    @Test("A missing settings.json is created cleanly with the 7 island hooks")
    func missingSettingsFileIsCreated() throws {
        let fixture = try SettingsFixture(contents: nil)
        let installer = HookInstaller(settingsURL: fixture.url)

        let outcome = try installer.install()

        #expect(outcome == .installed(backup: nil), "no pre-existing file, so no backup")
        let hooks = try #require(try fixture.readJSON()["hooks"] as? [String: Any])
        #expect(Set(hooks.keys) == Set(HookInstaller.events))
        for event in HookInstaller.events {
            let entries = try #require(hooks[event] as? [[String: Any]])
            #expect(entries.count == 1)
            #expect(Self.isIslandEntry(entries[0]))
        }
    }

    @Test("Settings without a hooks section gain one, other keys untouched, uninstall restores")
    func settingsWithoutHooksSection() throws {
        let fixture = try SettingsFixture(contents: #"{ "model": "fable" }"#)
        let installer = HookInstaller(settingsURL: fixture.url)

        try installer.install()
        let installed = try fixture.readJSON()
        #expect(installed["model"] as? String == "fable")
        #expect((installed["hooks"] as? [String: Any])?.count == HookInstaller.events.count)

        try installer.uninstall()
        let restored = try fixture.readJSON()
        #expect(NSDictionary(dictionary: restored) == ["model": "fable"] as NSDictionary)
    }

    @Test("A malformed settings.json is refused and never rewritten")
    func malformedSettingsIsNeverTouched() throws {
        let fixture = try SettingsFixture(contents: "{ not json at all")
        let before = try fixture.rawBytes()
        let installer = HookInstaller(settingsURL: fixture.url)

        #expect(throws: InstallerError.self) { try installer.install() }
        #expect(throws: InstallerError.self) { try installer.uninstall() }
        #expect(try fixture.rawBytes() == before)
    }

    /// Regression guard (FP #6): a backgrounded job's stdin is /dev/null under
    /// POSIX, so the hook command MUST capture the payload in the foreground
    /// before backgrounding curl. A "simplification" back to `--data-binary @-`
    /// would silently POST empty bodies with no other test noticing.
    @Test("The generated hook command captures stdin before backgrounding curl")
    func hookCommandCapturesStdinBeforeBackgrounding() throws {
        let command = HookInstaller.defaultCommand
        let capture = try #require(command.range(of: "payload=$(cat);"))
        let curl = try #require(command.range(of: "curl "))
        // The capture must come before curl is invoked.
        #expect(capture.upperBound <= curl.lowerBound)
        // The body is passed from the captured variable, never read from stdin.
        #expect(command.contains(#"--data-binary "$payload""#))
        #expect(!command.contains("@-"))
        // Fire-and-forget: time-bounded and backgrounded, so Claude Code is
        // never blocked when the app is down.
        #expect(command.contains("--max-time"))
        #expect(command.hasSuffix("&"))
    }

    static func isIslandEntry(_ entry: [String: Any]) -> Bool {
        entryCommands(entry).contains { $0.contains("127.0.0.1:41414/hooks/claude-code") }
    }

    static func isPixelAgentsEntry(_ entry: [String: Any]) -> Bool {
        entryCommands(entry).contains { $0.contains("pixel-agents") }
    }

    static func entryCommands(_ entry: [String: Any]) -> [String] {
        ((entry["hooks"] as? [[String: Any]]) ?? []).compactMap { $0["command"] as? String }
    }
}

/// A throwaway settings.json in a unique temporary directory.
struct SettingsFixture {
    let directory: URL
    let url: URL

    init(contents: String?) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-installer-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("settings.json")
        if let contents {
            try Data(contents.utf8).write(to: url)
        }
    }

    func readJSON() throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func rawBytes() throws -> Data {
        try Data(contentsOf: url)
    }
}
