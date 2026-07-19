import Foundation

/// Installs and uninstalls the island tee block in the user's statusline
/// script (issue #9, opt-in): a marked, fire-and-forget forward of the JSON
/// Claude Code pipes into the statusline, to the island local server.
///
/// Contract with the user's script:
/// - the block is inserted right AFTER the script's own stdin capture line
///   (`input=$(cat)`), reusing that variable — a backgrounded job's stdin is
///   /dev/null (POSIX), so the tee must never read stdin itself;
/// - the visual output of the script is never changed (curl backgrounded,
///   all its output discarded);
/// - a script without a stdin-capture line is refused, untouched;
/// - timestamped backup before any write, idempotent install, uninstall
///   removes the block and restores the original bytes exactly.
public struct StatuslineTeeInstaller {
    /// Block markers, HookInstaller-style: they identify the island block
    /// whatever the command inside, for a clean uninstall.
    public static let beginMarker = "# island-tee-begin"
    public static let endMarker = "# island-tee-end"

    /// Statusline endpoint of the island local server.
    public static let defaultEndpoint = "http://127.0.0.1:41414/statusline/claude-code"

    /// Production location of the user's statusline script.
    public static var defaultScriptURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/statusline-command.sh")
    }

    private let scriptURL: URL
    private let endpoint: String
    private let now: () -> Date

    public init(
        scriptURL: URL,
        endpoint: String = StatuslineTeeInstaller.defaultEndpoint,
        now: @escaping () -> Date = Date.init
    ) {
        self.scriptURL = scriptURL
        self.endpoint = endpoint
        self.now = now
    }

    /// The tee block, reusing the script's own capture variable. The payload
    /// travels as a curl argument — never via the background job's stdin —
    /// and every stream is discarded so the statusline output is untouched.
    func teeBlock(variable: String) -> String {
        """
        \(Self.beginMarker) (managed by island — do not edit)
        curl -s --max-time 1 -X POST "\(endpoint)?token=$(cat ~/.claude/island-token 2>/dev/null)" -H 'Content-Type: application/json' --data-binary "$\(variable)" >/dev/null 2>&1 &
        \(Self.endMarker)
        """
    }

    /// Inserts the tee block after the stdin capture line. Idempotent: a
    /// script already carrying the markers is left alone (no rewrite, no
    /// backup).
    @discardableResult
    public func install() throws -> TeeInstallOutcome {
        let contents = try readScript()
        guard !contents.contains(Self.beginMarker) else { return .alreadyInstalled }

        var lines = contents.components(separatedBy: "\n")
        guard let captureIndex = lines.firstIndex(where: { Self.captureVariable(of: $0) != nil }),
              let variable = Self.captureVariable(of: lines[captureIndex])
        else {
            throw TeeInstallerError.noStdinCapture(scriptURL)
        }

        lines.insert(teeBlock(variable: variable), at: captureIndex + 1)
        let backup = try backupExistingFile()
        try Data(lines.joined(separator: "\n").utf8).write(to: scriptURL, options: .atomic)
        return .installed(backup: backup)
    }

    /// Removes the island block — every other byte is left exactly as found.
    @discardableResult
    public func uninstall() throws -> TeeUninstallOutcome {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            return .nothingToUninstall
        }
        let contents = try readScript()
        var lines = contents.components(separatedBy: "\n")
        guard let begin = lines.firstIndex(where: { $0.hasPrefix(Self.beginMarker) }),
              let end = lines[begin...].firstIndex(where: { $0.hasPrefix(Self.endMarker) })
        else {
            return .nothingToUninstall
        }

        lines.removeSubrange(begin...end)
        let backup = try backupExistingFile()
        try Data(lines.joined(separator: "\n").utf8).write(to: scriptURL, options: .atomic)
        return .uninstalled(backup: backup)
    }

    /// The variable name of a POSIX stdin-capture line (`input=$(cat)`),
    /// or nil when the line is something else.
    static func captureVariable(of line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("=$(cat)") else { return nil }
        let name = String(trimmed.dropLast("=$(cat)".count))
        guard !name.isEmpty,
              name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
              !(name.first?.isNumber ?? true)
        else { return nil }
        return name
    }

    private func readScript() throws -> String {
        guard FileManager.default.fileExists(atPath: scriptURL.path) else {
            throw TeeInstallerError.missingScript(scriptURL)
        }
        guard let contents = try? String(contentsOf: scriptURL, encoding: .utf8) else {
            throw TeeInstallerError.unreadableScript(scriptURL)
        }
        return contents
    }

    /// Copies the current script, byte for byte, to a timestamped sibling
    /// before it gets rewritten (same convention as HookInstaller).
    private func backupExistingFile() throws -> URL? {
        try TimestampedBackup.create(of: scriptURL, at: now())
    }
}

public enum TeeInstallOutcome: Equatable, Sendable {
    /// The block was written; `backup` is the pre-write copy of the script.
    case installed(backup: URL?)
    /// The script already carries the island markers — nothing was touched.
    case alreadyInstalled
}

public enum TeeUninstallOutcome: Equatable, Sendable {
    /// The block was removed; `backup` is the pre-write copy of the script.
    case uninstalled(backup: URL?)
    /// No island block found — nothing was touched.
    case nothingToUninstall
}

public enum TeeInstallerError: Error, CustomStringConvertible, Equatable {
    /// There is no statusline script to tee from: nothing to do.
    case missingScript(URL)
    /// The script never captures stdin (`input=$(cat)`): inserting a tee
    /// would be unsafe (a backgrounded curl cannot read stdin), refuse.
    case noStdinCapture(URL)
    /// The script is not readable UTF-8: refuse to touch it.
    case unreadableScript(URL)

    public var description: String {
        switch self {
        case .missingScript(let url):
            return "no statusline script at \(url.path) — nothing to tee"
        case .noStdinCapture(let url):
            return "statusline script at \(url.path) has no stdin capture line (input=$(cat)) — refusing to insert the tee"
        case .unreadableScript(let url):
            return "statusline script at \(url.path) is not readable UTF-8 — refusing to modify it"
        }
    }
}
