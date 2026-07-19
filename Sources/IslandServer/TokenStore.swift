import Foundation
import Security

/// Manages the shared-secret token file (ADR-0001).
///
/// The token authenticates hook requests to the local server. It lives in a
/// user-only file (0600) — by default `~/.claude/island-token` — so hooks can
/// read it with `$(cat …)` while other users cannot.
public enum TokenStore {
    /// Default production location of the token file.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/island-token")
    }

    /// Returns the token, generating the file (0600) on first launch.
    public static func loadOrCreate(at url: URL = defaultURL) throws -> String {
        if let existing = try? String(contentsOf: url, encoding: .utf8) {
            let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }

        let token = generateToken()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(token.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
        return token
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed (\(status))")
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
