import Foundation

/// Shared backup convention of the island installers: before rewriting a
/// user file, copy it byte for byte to a timestamped
/// `<name>.island-backup-<stamp>` sibling (suffixed on collision).
enum TimestampedBackup {
    /// Returns nil when there is no file to back up yet.
    static func create(of url: URL, at date: Date) throws -> URL? {
        guard let original = try? Data(contentsOf: url) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: date)
        var backup = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).island-backup-\(stamp)")
        var counter = 1
        while FileManager.default.fileExists(atPath: backup.path) {
            backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(url.lastPathComponent).island-backup-\(stamp)-\(counter)")
            counter += 1
        }
        try original.write(to: backup, options: .atomic)
        return backup
    }
}
