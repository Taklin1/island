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

    /// Extracts the question the Session is currently blocked on (issue #26):
    /// the last `AskUserQuestion` tool_use that has **no** matching `tool_result`
    /// yet — i.e. the one still awaiting the user. Local parse only (ADR-0002),
    /// the format is the one frozen by spike #25 (`input.questions[]`, each with
    /// ordered `options[]` of `{label, description}`).
    ///
    /// Defensive like the rest of the reader — returns `nil` (the card then
    /// degrades to Click-to-focus, US10) whenever the pending call is not a
    /// clean single question with options: an already-answered question, a
    /// permission/free-text block with no `AskUserQuestion` at all, an empty or
    /// unreadable `options`, or a turn posing **several** questions (N>1: the
    /// index→key mapping would be ambiguous, so we never fake buttons).
    ///
    /// - Returns: the pending question, or `nil` when none is extractable.
    public static func pendingQuestion(
        ofTranscriptAt url: URL,
        maxTailBytes: Int = defaultMaxTailBytes
    ) -> PendingQuestion? {
        guard let lines = tailLines(of: url, maxBytes: maxTailBytes) else { return nil }

        // Walking backwards, a `tool_result` seen *first* means its tool_use is
        // already answered: track those ids so a resolved question of an earlier
        // tour is never resurfaced.
        var answered: Set<String> = []

        for raw in lines.reversed() {
            guard let line = TranscriptLine(jsonLine: raw) else { continue }
            guard line.isSidechain != true, line.isMeta != true else { continue }

            switch line.type {
            case "assistant":
                for block in (line.message?.content ?? []).reversed() {
                    guard block.type == "tool_use", block.name == "AskUserQuestion" else { continue }
                    if let id = block.id, answered.contains(id) { continue }
                    // The most recent unanswered AskUserQuestion is THE pending
                    // one: extract it, or degrade — never fall back to an older.
                    return pendingQuestion(from: block)
                }
            case "user":
                let blocks = line.message?.content ?? []
                for block in blocks where block.type == "tool_result" {
                    if let id = block.toolUseID { answered.insert(id) }
                }
                // The last real prompt (no tool_result) bounds the turn: nothing
                // before it can be the pending question.
                if !blocks.contains(where: { $0.type == "tool_result" }) {
                    return nil
                }
            default:
                continue
            }
        }
        return nil
    }

    /// Turns one `AskUserQuestion` tool_use block into a ``PendingQuestion``,
    /// or `nil` when it is not a clean single question with options.
    private static func pendingQuestion(
        from block: TranscriptLine.Block
    ) -> PendingQuestion? {
        // N>1 questions in one turn would need a per-question key mapping the
        // single button row cannot honestly express (spike #25 open point) →
        // degrade rather than show misleading buttons.
        guard let questions = block.input?.questions, questions.count == 1,
            let question = questions.first,
            let prompt = question.question?.trimmingCharacters(in: .whitespacesAndNewlines),
            !prompt.isEmpty
        else { return nil }

        let options: [PendingQuestion.Option] = (question.options ?? []).compactMap { option in
            guard let label = option.label?.trimmingCharacters(in: .whitespacesAndNewlines),
                !label.isEmpty
            else { return nil }
            let description = option.description?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PendingQuestion.Option(
                label: label,
                description: (description?.isEmpty ?? true) ? nil : description
            )
        }
        // No extractable options (free text, empty/unreadable list) → degrade.
        guard !options.isEmpty else { return nil }
        return PendingQuestion(prompt: prompt, options: options)
    }

    /// Extracts the current session title (issue #32) from the transcript.
    ///
    /// Claude Code writes titles on their own JSONL lines, and the two kinds are
    /// *distinct record types* (verified against real transcripts):
    /// - a manual `/rename` writes `{"type":"custom-title","customTitle":"…"}`;
    /// - the auto-generated title is `{"type":"ai-title","aiTitle":"…"}`, which
    ///   Claude Code re-emits as the conversation grows but *never* updates on a
    ///   `/rename` — it stays frozen on the first auto value.
    ///
    /// So the resolution is: the **last `custom-title` wins whenever one exists**
    /// (a manual rename always takes precedence, even though frozen `ai-title`
    /// re-emissions keep appearing after it in the file); otherwise the **last
    /// `ai-title`**; otherwise `nil` (the caller falls back to the folder name).
    ///
    /// Reads the same generous tail as ``summary(ofTranscriptAt:)`` (4 MB): the
    /// last title record can sit far from EOF when a single turn produced a lot
    /// of output, and a too-small cap silently misses it. A cheap substring
    /// pre-filter keeps the scan fast — only the handful of title lines are ever
    /// JSON-decoded. Defensive like the summary: a missing/unreadable/titleless
    /// transcript returns `nil`.
    ///
    /// - Returns: the current title, or `nil` when none is present in the tail.
    public static func title(
        ofTranscriptAt url: URL,
        maxTailBytes: Int = defaultMaxTailBytes
    ) -> String? {
        guard let lines = tailLines(of: url, maxBytes: maxTailBytes) else { return nil }

        var latestAutoTitle: String?
        // Walk backwards: the first custom-title met is the most recent manual
        // /rename and wins outright; otherwise keep the most recent ai-title as
        // the fallback (the frozen auto title).
        for raw in lines.reversed() {
            guard raw.range(of: "-title") != nil,
                let line = TranscriptLine(jsonLine: raw)
            else { continue }

            switch line.type {
            case "custom-title":
                if let title = line.customTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !title.isEmpty {
                    return title
                }
            case "ai-title":
                if latestAutoTitle == nil,
                    let title = line.aiTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                    !title.isEmpty {
                    latestAutoTitle = title
                }
            default:
                break
            }
        }
        return latestAutoTitle
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
    /// Auto-generated title, carried by `type: "ai-title"` lines (issue #32).
    let aiTitle: String?
    /// Manual `/rename` title, carried by `type: "custom-title"` lines (#32).
    let customTitle: String?
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
        /// tool_use id — matched against a later `tool_result`'s `tool_use_id`
        /// so an already-answered AskUserQuestion is never resurfaced (#26).
        let id: String?
        /// A `tool_result`'s back-reference to the tool_use it answers.
        let toolUseID: String?

        init(
            type: String? = nil, text: String? = nil, name: String? = nil,
            input: ToolInput? = nil, id: String? = nil, toolUseID: String? = nil
        ) {
            self.type = type
            self.text = text
            self.name = name
            self.input = input
            self.id = id
            self.toolUseID = toolUseID
        }

        enum CodingKeys: String, CodingKey {
            case type, text, name, input, id
            case toolUseID = "tool_use_id"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try? container.decode(String.self, forKey: .type)
            text = try? container.decode(String.self, forKey: .text)
            name = try? container.decode(String.self, forKey: .name)
            input = try? container.decode(ToolInput.self, forKey: .input)
            id = try? container.decode(String.self, forKey: .id)
            toolUseID = try? container.decode(String.self, forKey: .toolUseID)
        }
    }

    /// Subset of tool_use inputs the summary and the pending-question extraction
    /// care about.
    struct ToolInput: Decodable {
        let filePath: String?
        let notebookPath: String?
        let todos: [Todo]?
        /// AskUserQuestion payload (spike #25): an ordered list of questions.
        let questions: [Question]?

        enum CodingKeys: String, CodingKey {
            case filePath = "file_path"
            case notebookPath = "notebook_path"
            case todos
            case questions
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            filePath = try? container.decode(String.self, forKey: .filePath)
            notebookPath = try? container.decode(String.self, forKey: .notebookPath)
            todos = try? container.decode([Todo].self, forKey: .todos)
            questions = try? container.decode([Question].self, forKey: .questions)
        }
    }

    struct Todo: Decodable {
        let content: String?
        let status: String?
    }

    /// One AskUserQuestion entry (spike #25): a label, a header, a multi-select
    /// flag, and ordered options.
    struct Question: Decodable {
        let question: String?
        let header: String?
        let multiSelect: Bool?
        let options: [Option]?
    }

    /// One ordered option of an AskUserQuestion (`{label, description}`).
    struct Option: Decodable {
        let label: String?
        let description: String?
    }
}
