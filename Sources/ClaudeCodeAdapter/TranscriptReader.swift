import Foundation
import IslandStore

/// Extracts a ``TurnSummary`` from a Claude Code transcript (ADR-0002):
/// pure local parsing of the session JSONL, never an LLM call.
///
/// The transcript format is undocumented and changes across Claude Code
/// versions, so everything here is defensive: every field is optional, any
/// unparseable line is skipped, and any failure returns `nil` — the caller
/// falls back to "state + project" and the notification always goes out.
///
/// Transcripts grow to several megabytes: only a bounded tail of the file is
/// ever read, never the whole file.
public enum TranscriptReader {
    /// How much of the end of the transcript is read at most.
    public static let defaultMaxTailBytes = 4 * 1024 * 1024

    /// Reads the transcript tail and summarizes the last main turn.
    ///
    /// - Returns: the summary, or `nil` when the file is missing, unreadable,
    ///   or contains nothing summarizable (the caller must still notify).
    public static func summary(
        ofTranscriptAt url: URL,
        maxTailBytes: Int = defaultMaxTailBytes
    ) -> TurnSummary? {
        guard let lines = tailLines(of: url, maxBytes: maxTailBytes) else { return nil }

        var text: String?
        var todosDone: Int?
        var todosTotal: Int?
        var filesModified: [String] = []
        var turnEndedAt: Date?
        var turnStartedAt: Date?

        // Walk backwards from the end of the transcript, and stop at the user
        // prompt that started the last turn: everything in between belongs to
        // the main turn. The first assistant text found on the way is the end
        // of the last assistant message.
        for raw in lines.reversed() {
            guard let line = TranscriptLine(jsonLine: raw) else { continue }
            guard line.isSidechain != true, line.isMeta != true else { continue }

            switch line.type {
            case "assistant":
                if turnEndedAt == nil {
                    turnEndedAt = parseTimestamp(line.timestamp)
                }
                for block in (line.message?.content ?? []).reversed() {
                    switch block.type {
                    case "text":
                        if text == nil, let t = block.text, !t.isEmpty {
                            text = t
                        }
                    case "tool_use":
                        collect(
                            toolUse: block,
                            todosDone: &todosDone, todosTotal: &todosTotal,
                            filesModified: &filesModified
                        )
                    default:
                        break
                    }
                }
            case "user":
                // tool_result lines are also `type: user`; the turn starts at
                // the last real prompt (no tool_result block in its content).
                let blocks = line.message?.content ?? []
                guard !blocks.contains(where: { $0.type == "tool_result" }) else { continue }
                turnStartedAt = parseTimestamp(line.timestamp)
            default:
                continue
            }

            if turnStartedAt != nil { break }
        }

        let duration: TimeInterval? =
            if let turnStartedAt, let turnEndedAt, turnEndedAt >= turnStartedAt {
                turnEndedAt.timeIntervalSince(turnStartedAt)
            } else {
                nil
            }

        let summary = TurnSummary(
            text: text,
            todosDone: todosDone,
            todosTotal: todosTotal,
            filesModified: filesModified,
            turnDuration: duration
        )
        guard summary != TurnSummary() else { return nil }
        return summary
    }

    /// Extracts the current session title (issue #32) from the transcript.
    ///
    /// Claude Code writes the title on its own JSONL line
    /// (`{"type":"ai-title","aiTitle":"…"}`) inside a metadata cluster it emits
    /// around prompt boundaries, re-emitting it as the conversation grows;
    /// `/rename` makes a later cluster carry the new value. Walking the tail
    /// backwards and returning the first `ai-title` found therefore yields the
    /// *current* title, reflecting a rename.
    ///
    /// Reads the same generous tail as ``summary(ofTranscriptAt:)`` (4 MB): the
    /// last title cluster can sit far from EOF when a single turn produced a lot
    /// of output, and a too-small cap silently missed it (the bug behind #32's
    /// first fix). A cheap substring pre-filter keeps the scan fast even on the
    /// full tail — only the handful of `ai-title` lines are ever JSON-decoded.
    /// Defensive like the summary: a missing/unreadable/titleless transcript
    /// returns `nil` and the caller falls back to the project folder name.
    ///
    /// - Returns: the current title, or `nil` when none is present in the tail.
    public static func title(
        ofTranscriptAt url: URL,
        maxTailBytes: Int = defaultMaxTailBytes
    ) -> String? {
        guard let lines = tailLines(of: url, maxBytes: maxTailBytes) else { return nil }

        for raw in lines.reversed() {
            guard raw.range(of: "ai-title") != nil,
                let line = TranscriptLine(jsonLine: raw), line.type == "ai-title" else {
                continue
            }
            let title = line.aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let title, !title.isEmpty { return title }
        }
        return nil
    }

    /// Tool names whose `file_path`-shaped input means "this file changed".
    private static let fileModifyingTools: Set<String> = [
        "Edit", "Write", "MultiEdit", "NotebookEdit",
    ]

    /// Harvests todos and modified files from one tool_use block, walking
    /// backwards: the *last* TodoWrite of the turn wins, and files keep their
    /// chronological order.
    private static func collect(
        toolUse block: TranscriptLine.Block,
        todosDone: inout Int?, todosTotal: inout Int?,
        filesModified: inout [String]
    ) {
        guard let name = block.name else { return }

        if name == "TodoWrite", todosTotal == nil, let todos = block.input?.todos {
            todosTotal = todos.count
            todosDone = todos.count(where: { $0.status == "completed" })
        }

        if fileModifyingTools.contains(name),
            let path = block.input?.filePath ?? block.input?.notebookPath,
            !filesModified.contains(path) {
            filesModified.insert(path, at: 0)
        }
    }

    /// Transcript timestamps are ISO8601 with fractional seconds; older or
    /// future versions may drop the fraction.
    private static func parseTimestamp(_ string: String?) -> Date? {
        guard let string else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: string)
            ?? ISO8601DateFormatter().date(from: string)
    }

    // MARK: - Bounded tail reading

    /// Returns the complete lines found in the last `maxBytes` of the file.
    /// When the file is bigger than the cap, the first (likely partial) line
    /// of the window is dropped.
    private static func tailLines(of url: URL, maxBytes: Int) -> [Substring]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let size = try? handle.seekToEnd(), size > 0 else { return nil }
        let offset = size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0
        guard (try? handle.seek(toOffset: offset)) != nil,
            let data = try? handle.readToEnd(),
            let contents = String(data: data, encoding: .utf8)
        else { return nil }

        var lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        if offset > 0, !lines.isEmpty {
            lines.removeFirst()
        }
        return lines
    }
}

// MARK: - Defensive line model

/// One transcript line. Every field is optional: a missing or reshaped field
/// must never fail the whole extraction.
struct TranscriptLine: Decodable {
    let type: String?
    let isSidechain: Bool?
    let isMeta: Bool?
    let timestamp: String?
    /// Session title carried by `type: "ai-title"` lines (issue #32).
    let aiTitle: String?
    let message: Message?

    init?(jsonLine: Substring) {
        guard
            let decoded = try? JSONDecoder().decode(
                TranscriptLine.self, from: Data(jsonLine.utf8))
        else { return nil }
        self = decoded
    }

    struct Message: Decodable {
        let id: String?
        let role: String?
        /// Content blocks; a plain-string content (real user prompts) decodes
        /// as a single text block.
        let content: [Block]?

        enum CodingKeys: String, CodingKey {
            case id, role, content
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try? container.decode(String.self, forKey: .id)
            role = try? container.decode(String.self, forKey: .role)
            if let string = try? container.decode(String.self, forKey: .content) {
                content = [Block(type: "text", text: string)]
            } else {
                content = try? container.decode([Block].self, forKey: .content)
            }
        }

        init(id: String? = nil, role: String? = nil, content: [Block]? = nil) {
            self.id = id
            self.role = role
            self.content = content
        }
    }

    /// One content block of a message (text, tool_use, tool_result, thinking…).
    struct Block: Decodable {
        let type: String?
        let text: String?
        let name: String?
        let input: ToolInput?

        init(type: String? = nil, text: String? = nil, name: String? = nil, input: ToolInput? = nil) {
            self.type = type
            self.text = text
            self.name = name
            self.input = input
        }
    }

    /// Subset of tool_use inputs the summary cares about.
    struct ToolInput: Decodable {
        let filePath: String?
        let notebookPath: String?
        let todos: [Todo]?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case notebookPath = "notebook_path"
            case todos
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filePath = try? container.decode(String.self, forKey: .filePath)
            notebookPath = try? container.decode(String.self, forKey: .notebookPath)
            todos = try? container.decode([Todo].self, forKey: .todos)
        }
    }

    struct Todo: Decodable {
        let content: String?
        let status: String?
    }
}
