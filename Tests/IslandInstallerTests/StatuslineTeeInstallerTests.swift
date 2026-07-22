import Foundation
import Testing
import IslandInstaller

/// Statusline tee seam (issue #9): fixture scripts on disk in, resulting
/// script out. All tests operate on temporary fixture files — never on the
/// real ~/.claude/statusline-command.sh. The visual-output contract is
/// checked by actually running the fixture script with sh.
struct StatuslineTeeInstallerTests {
    /// Mirrors the real script's structure: shebang, `input=$(cat)` capture
    /// on line 2, then processing that reuses `$input`.
    static let scriptFixture = """
    #!/bin/sh
    input=$(cat)

    model=$(printf '%s' "$input" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin).get("model",{}).get("display_name",""))')
    printf 'model=%s\\n' "$model"
    """

    static let statuslineJSON = """
    {"session_id":"tee-fixture-1","model":{"display_name":"Opus"}}
    """

    /// Unroutable test endpoint: the tee must never hit a real island
    /// instance (port 41414) from the test suite.
    static let testEndpoint = "http://127.0.0.1:41999/statusline/claude-code"

    @Test("Install inserts the marked tee block after the stdin capture, without changing the script output")
    func installInsertsBlockAndPreservesOutput() throws {
        let fixture = try ScriptFixture(contents: Self.scriptFixture)
        let before = try fixture.run(stdin: Self.statuslineJSON)
        let installer = StatuslineTeeInstaller(scriptURL: fixture.url, endpoint: Self.testEndpoint)

        let outcome = try installer.install()

        guard case .installed(let backup) = outcome else {
            Issue.record("expected .installed, got \(outcome)")
            return
        }
        let contents = try fixture.readText()
        #expect(contents.contains(StatuslineTeeInstaller.beginMarker))
        #expect(contents.contains(StatuslineTeeInstaller.endMarker))
        // The block reuses the script's own capture variable, right after it:
        // a backgrounded curl gets /dev/null as stdin (POSIX), so it must
        // never read the payload from stdin itself.
        let lines = contents.components(separatedBy: "\n")
        let captureIndex = try #require(lines.firstIndex(of: "input=$(cat)"))
        #expect(lines[captureIndex + 1].hasPrefix(StatuslineTeeInstaller.beginMarker))
        #expect(contents.contains(#"--data-binary "$input""#))

        // Backup is a byte-exact copy of the original.
        let backupURL = try #require(backup)
        #expect(try Data(contentsOf: backupURL) == Data(Self.scriptFixture.utf8))

        // Visual contract: same stdin, byte-identical stdout.
        let after = try fixture.run(stdin: Self.statuslineJSON)
        #expect(after == before)
    }

    @Test("Installing twice is idempotent: second run touches nothing")
    func installIsIdempotent() throws {
        let fixture = try ScriptFixture(contents: Self.scriptFixture)
        let installer = StatuslineTeeInstaller(scriptURL: fixture.url, endpoint: Self.testEndpoint)
        try installer.install()
        let onceInstalled = try fixture.rawBytes()

        let outcome = try installer.install()

        #expect(outcome == .alreadyInstalled)
        #expect(try fixture.rawBytes() == onceInstalled)
        // No second backup either.
        let backups = try FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)
            .filter { $0.contains("island-backup") }
        #expect(backups.count == 1)
    }

    @Test("Uninstall removes the block and restores the original bytes exactly")
    func uninstallRestoresOriginalBytes() throws {
        let fixture = try ScriptFixture(contents: Self.scriptFixture)
        let installer = StatuslineTeeInstaller(scriptURL: fixture.url, endpoint: Self.testEndpoint)
        try installer.install()

        let outcome = try installer.uninstall()

        guard case .uninstalled = outcome else {
            Issue.record("expected .uninstalled, got \(outcome)")
            return
        }
        #expect(try fixture.rawBytes() == Data(Self.scriptFixture.utf8))

        // Uninstalling again touches nothing.
        #expect(try installer.uninstall() == .nothingToUninstall)
    }

    @Test("A script without a stdin capture line is refused, untouched")
    func scriptWithoutStdinCaptureIsRefused() throws {
        let noCapture = """
        #!/bin/sh
        jq -r '.model.display_name'
        """
        let fixture = try ScriptFixture(contents: noCapture)
        let installer = StatuslineTeeInstaller(scriptURL: fixture.url, endpoint: Self.testEndpoint)

        #expect(throws: TeeInstallerError.noStdinCapture(fixture.url)) {
            try installer.install()
        }
        #expect(try fixture.rawBytes() == Data(noCapture.utf8))
    }

    @Test("A missing script is an error on install, a no-op on uninstall")
    func missingScriptHandling() throws {
        let fixture = try ScriptFixture(contents: nil)
        let installer = StatuslineTeeInstaller(scriptURL: fixture.url, endpoint: Self.testEndpoint)

        #expect(throws: TeeInstallerError.missingScript(fixture.url)) {
            try installer.install()
        }
        #expect(try installer.uninstall() == .nothingToUninstall)
        #expect(!FileManager.default.fileExists(atPath: fixture.url.path))
    }

    @Test("The capture variable name is reused whatever the script calls it")
    func captureVariableIsReused() throws {
        let payloadScript = """
        #!/bin/sh
        payload=$(cat)
        printf '%s' "$payload" | jq -r '.model.display_name // empty'
        """
        let fixture = try ScriptFixture(contents: payloadScript)
        let installer = StatuslineTeeInstaller(scriptURL: fixture.url, endpoint: Self.testEndpoint)

        try installer.install()

        #expect(try fixture.readText().contains(#"--data-binary "$payload""#))
    }
}

/// Temporary on-disk statusline script fixture, runnable with sh.
struct ScriptFixture {
    let directory: URL
    let url: URL

    init(contents: String?) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("island-tee-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appendingPathComponent("statusline-command.sh")
        if let contents {
            try Data(contents.utf8).write(to: url)
        }
    }

    func readText() throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    func rawBytes() throws -> Data {
        try Data(contentsOf: url)
    }

    /// Runs the script with sh, piping `stdin` in, and returns raw stdout —
    /// exactly how Claude Code invokes a statusline command.
    func run(stdin: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [url.path]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }
}
