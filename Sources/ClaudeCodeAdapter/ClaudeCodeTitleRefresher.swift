import Foundation

/// Re-reads Session titles on demand (issue #32), covering the case the
/// per-event read cannot: a `/rename` on a Session that is idle or has ended
/// fires no further hook, so nothing re-reads its transcript — yet the Extended
/// Island must still show the new title when the user hovers.
///
/// It remembers each Session's transcript path from the raw hook payloads it
/// sees (the path is Claude Code-specific and never leaves this adapter layer,
/// ADR-0004: the UI/store only deal with the generic title). The controller
/// triggers a refresh on hover through an injected closure; the wiring here does
/// the actual transcript read.
///
/// Thread-safe: `observe` runs on the server queue (off-main) while
/// `currentTitle` runs on the main actor during hover.
public final class ClaudeCodeTitleRefresher: @unchecked Sendable {
    private let lock = NSLock()
    private var transcriptPaths: [String: String] = [:]

    public init() {}

    /// Records the transcript path carried by any raw hook payload. Cheap: it
    /// decodes only the two fields it needs and ignores everything else.
    public func observe(hookPayload data: Data) {
        guard let ref = try? JSONDecoder().decode(SessionRef.self, from: data),
            let path = ref.transcriptPath, !path.isEmpty
        else { return }
        lock.lock()
        transcriptPaths[ref.sessionID] = path
        lock.unlock()
    }

    /// The current title of a known Session, re-read from its transcript, or
    /// `nil` when the Session is unknown or its transcript carries no title.
    public func currentTitle(forSessionID id: String) -> String? {
        lock.lock()
        let path = transcriptPaths[id]
        lock.unlock()
        return path.flatMap { TranscriptReader.title(ofTranscriptAt: URL(fileURLWithPath: $0)) }
    }

    /// Minimal view of a hook payload: just what pins a Session to its file.
    private struct SessionRef: Decodable {
        let sessionID: String
        let transcriptPath: String?

        enum CodingKeys: String, CodingKey {
            case sessionID = "session_id"
            case transcriptPath = "transcript_path"
        }
    }
}
