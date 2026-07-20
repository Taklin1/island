import Foundation
import IslandStore
import Testing

@testable import ClaudeCodeAdapter

/// Fixture lines mirror the real Claude Code transcript JSONL shape
/// (observed on v2.1.215), anonymized: fake session ids, neutral cwd and
/// contents. One JSON object per line; a logical assistant message spans
/// several lines sharing `message.id` (thinking / text / tool_use blocks).
private enum TranscriptFixtures {
    static let sessionTail = """
        {"parentUuid":null,"isSidechain":false,"promptId":"p-1","type":"user","message":{"role":"user","content":"Fix the parser crash"},"uuid":"u-1","timestamp":"2026-07-19T10:00:00.000Z","permissionMode":"default","promptSource":"user","userType":"external","entrypoint":"cli","cwd":"/Users/dev/projects/demo","sessionId":"11111111-2222-3333-4444-555555555555","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"u-1","isSidechain":false,"type":"assistant","message":{"id":"msg_01A","type":"message","role":"assistant","model":"claude-test","content":[{"type":"thinking","thinking":"Let me look at the parser.","signature":"sig"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":2,"output_tokens":9}},"requestId":"req_1","uuid":"a-1","timestamp":"2026-07-19T10:00:05.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"a-1","isSidechain":false,"type":"assistant","message":{"id":"msg_01A","type":"message","role":"assistant","model":"claude-test","content":[{"type":"tool_use","id":"toolu_01","name":"Edit","input":{"file_path":"/Users/dev/projects/demo/Sources/App/Parser.swift","old_string":"a","new_string":"b"}}],"stop_reason":"tool_use"},"requestId":"req_1","uuid":"a-2","timestamp":"2026-07-19T10:00:09.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"a-2","isSidechain":false,"promptId":"p-1","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_01","type":"tool_result","content":"ok"}]},"toolUseResult":{"filePath":"/Users/dev/projects/demo/Sources/App/Parser.swift"},"uuid":"u-2","timestamp":"2026-07-19T10:00:10.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"u-2","isSidechain":false,"type":"assistant","message":{"id":"msg_01B","type":"message","role":"assistant","model":"claude-test","content":[{"type":"tool_use","id":"toolu_02","name":"TodoWrite","input":{"todos":[{"content":"Fix the crash","status":"completed","activeForm":"Fixing the crash"},{"content":"Add a regression test","status":"in_progress","activeForm":"Adding a regression test"},{"content":"Update the changelog","status":"pending","activeForm":"Updating the changelog"}]}}],"stop_reason":"tool_use"},"requestId":"req_2","uuid":"a-3","timestamp":"2026-07-19T10:01:00.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"a-3","isSidechain":false,"promptId":"p-1","type":"user","message":{"role":"user","content":[{"tool_use_id":"toolu_02","type":"tool_result","content":"Todos updated"}]},"uuid":"u-3","timestamp":"2026-07-19T10:01:01.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"u-3","isSidechain":false,"type":"assistant","message":{"id":"msg_01C","type":"message","role":"assistant","model":"claude-test","content":[{"type":"text","text":"Fixed the parser crash.\\n\\n- `parse()` now returns nil on empty input\\n- added a regression test"}],"stop_reason":null,"stop_sequence":null,"usage":{"input_tokens":2,"output_tokens":40}},"requestId":"req_3","uuid":"a-4","timestamp":"2026-07-19T10:03:20.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"a-4","isSidechain":false,"type":"system","subtype":"stop_hook_summary","hookCount":1,"hookErrors":[],"level":"suggestion","timestamp":"2026-07-19T10:03:21.000Z","uuid":"s-1","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        """

    /// Sidechain traffic appended after the main-turn text: a subagent's
    /// prompt, an Edit and a final report, all flagged `isSidechain: true`
    /// (the pre-2.x inline sidechain shape).
    static let sidechainTail = sessionTail + "\n" + """
        {"parentUuid":"a-4","isSidechain":true,"promptId":"p-1","type":"user","message":{"role":"user","content":"You are a subagent, refactor the tests"},"uuid":"sc-1","timestamp":"2026-07-19T10:03:25.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"sc-1","isSidechain":true,"type":"assistant","message":{"id":"msg_02A","type":"message","role":"assistant","model":"claude-test","content":[{"type":"tool_use","id":"toolu_03","name":"Edit","input":{"file_path":"/Users/dev/projects/demo/Tests/AppTests/ParserTests.swift","old_string":"x","new_string":"y"}}],"stop_reason":"tool_use"},"requestId":"req_4","uuid":"sc-2","timestamp":"2026-07-19T10:03:30.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        {"parentUuid":"sc-2","isSidechain":true,"type":"assistant","message":{"id":"msg_02B","type":"message","role":"assistant","model":"claude-test","content":[{"type":"text","text":"Subagent report: tests refactored."}],"stop_reason":null},"requestId":"req_5","uuid":"sc-3","timestamp":"2026-07-19T10:03:40.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
        """

    /// An AUTO-generated title record (issue #32): `type:"ai-title"`. Claude
    /// Code re-emits it as the conversation grows and NEVER changes it on a
    /// `/rename` — it stays frozen on the first auto value.
    static func aiTitleLine(_ title: String) -> String {
        #"{"type":"ai-title","aiTitle":"\#(title)","sessionId":"11111111-2222-3333-4444-555555555555"}"#
    }

    /// A MANUAL `/rename` record (issue #32): a DISTINCT `type:"custom-title"`
    /// with a `customTitle` field (verified against real transcripts).
    static func customTitleLine(_ title: String) -> String {
        #"{"type":"custom-title","customTitle":"\#(title)","sessionId":"11111111-2222-3333-4444-555555555555"}"#
    }

    /// Writes a fixture to a unique temp file and returns its URL.
    static func write(_ contents: String, name: String = UUID().uuidString) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-fixture-\(name).jsonl")
        try! Data(contents.utf8).write(to: url)
        return url
    }
}

struct TranscriptReaderTests {
    @Test("A real transcript tail yields the last assistant message of the main turn")
    func lastAssistantMessage() throws {
        let url = TranscriptFixtures.write(TranscriptFixtures.sessionTail)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try #require(TranscriptReader.summary(ofTranscriptAt: url))
        #expect(summary.text == """
            Fixed the parser crash.

            - `parse()` now returns nil on empty input
            - added a regression test
            """)
    }

    @Test("The turn's todo state, modified files and duration are extracted")
    func todosFilesAndDuration() throws {
        let url = TranscriptFixtures.write(TranscriptFixtures.sessionTail)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try #require(TranscriptReader.summary(ofTranscriptAt: url))
        #expect(summary.todosDone == 1)
        #expect(summary.todosTotal == 3)
        #expect(summary.filesModified == ["/Users/dev/projects/demo/Sources/App/Parser.swift"])
        // 10:00:00Z (prompt) -> 10:03:20Z (last assistant message).
        #expect(summary.turnDuration == 200)
    }

    @Test("Sidechain messages are never the main turn's summary")
    func sidechainsExcluded() throws {
        let url = TranscriptFixtures.write(TranscriptFixtures.sidechainTail)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try #require(TranscriptReader.summary(ofTranscriptAt: url))
        #expect(summary.text?.hasPrefix("Fixed the parser crash.") == true)
        // The subagent's Edit does not count as a main-turn modification.
        #expect(summary.filesModified == ["/Users/dev/projects/demo/Sources/App/Parser.swift"])
    }

    @Test("A missing transcript falls back to nil without crashing")
    func missingTranscript() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-fixture-\(UUID().uuidString)-missing.jsonl")
        #expect(TranscriptReader.summary(ofTranscriptAt: url) == nil)
    }

    @Test("A fully corrupted transcript falls back to nil without crashing")
    func corruptedTranscript() {
        let url = TranscriptFixtures.write("""
            this is not json at all
            {"truncated": "object", "missing brace
            \u{0}\u{1}binary garbage\u{FFFD}
            42
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(TranscriptReader.summary(ofTranscriptAt: url) == nil)
    }

    @Test("Corrupted lines inside an otherwise valid transcript are skipped")
    func corruptedLinesSkipped() throws {
        let lines = TranscriptFixtures.sessionTail.split(separator: "\n")
        let polluted = lines.enumerated()
            .flatMap { [$0.element, "{\"broken\": line \($0.offset)"] }
            .joined(separator: "\n")
        let url = TranscriptFixtures.write(polluted)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try #require(TranscriptReader.summary(ofTranscriptAt: url))
        #expect(summary.text?.hasPrefix("Fixed the parser crash.") == true)
        #expect(summary.turnDuration == 200)
    }

    @Test("A multi-megabyte transcript is summarized from its tail only")
    func bigTranscriptReadFromEnd() throws {
        // A huge preamble of older turns, far beyond the read cap: the reader
        // must still summarize the last turn without loading the whole file.
        let oldTurn = """
            {"parentUuid":null,"isSidechain":false,"type":"user","message":{"role":"user","content":"An older prompt"},"uuid":"old-u","timestamp":"2026-07-19T09:00:00.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
            {"parentUuid":"old-u","isSidechain":false,"type":"assistant","message":{"id":"msg_00","type":"message","role":"assistant","model":"claude-test","content":[{"type":"text","text":"An older answer that must not win."}],"stop_reason":null},"uuid":"old-a","timestamp":"2026-07-19T09:00:10.000Z","sessionId":"11111111-2222-3333-4444-555555555555","cwd":"/Users/dev/projects/demo","version":"2.1.215","gitBranch":"main"}
            """
        let preamble = Array(repeating: oldTurn, count: 2000).joined(separator: "\n")
        let url = TranscriptFixtures.write(preamble + "\n" + TranscriptFixtures.sessionTail)
        defer { try? FileManager.default.removeItem(at: url) }

        let summary = try #require(
            TranscriptReader.summary(ofTranscriptAt: url, maxTailBytes: 64 * 1024))
        #expect(summary.text?.hasPrefix("Fixed the parser crash.") == true)
        #expect(summary.turnDuration == 200)
    }

    // MARK: - Session title (issue #32)
    //
    // /rename writes a DISTINCT `custom-title` record; `ai-title` is the
    // auto-generated title and never changes on rename. The manual rename
    // always wins. Fixtures mirror the real transcript structures.

    @Test("(d) With only an ai-title, the auto title is used")
    func autoTitleUsedWhenNoRename() throws {
        let url = TranscriptFixtures.write(
            TranscriptFixtures.aiTitleLine("Ghostty redirection not working") + "\n"
                + TranscriptFixtures.sessionTail)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptReader.title(ofTranscriptAt: url) == "Ghostty redirection not working")
    }

    @Test("(c) With only a custom-title, the manual rename is used")
    func customTitleUsedWhenNoAutoTitle() throws {
        let url = TranscriptFixtures.write(
            TranscriptFixtures.sessionTail + "\n" + TranscriptFixtures.customTitleLine("TEST ?"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptReader.title(ofTranscriptAt: url) == "TEST ?")
    }

    @Test("(a) An ai-title then a later /rename: the custom-title wins")
    func renameOverridesEarlierAutoTitle() throws {
        let url = TranscriptFixtures.write(
            TranscriptFixtures.aiTitleLine("Auto generated title") + "\n"
                + TranscriptFixtures.sessionTail + "\n"
                + TranscriptFixtures.customTitleLine("Renamed by the user"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptReader.title(ofTranscriptAt: url) == "Renamed by the user")
    }

    @Test("(b) A /rename then MORE RECENT frozen ai-titles: the custom-title still wins")
    func renameWinsEvenWhenAutoTitleIsMoreRecent() throws {
        // The exact real shape: after a manual rename, Claude Code keeps
        // re-emitting the (frozen) auto ai-title AFTER the custom-title. The
        // rename must still win despite sitting earlier in the file.
        let autoReemissions = Array(
            repeating: TranscriptFixtures.aiTitleLine("Ghostty redirection not working"),
            count: 5
        ).joined(separator: "\n")
        let url = TranscriptFixtures.write(
            TranscriptFixtures.customTitleLine("Titre A") + "\n"
                + TranscriptFixtures.customTitleLine("TEST ?") + "\n"
                + autoReemissions)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptReader.title(ofTranscriptAt: url) == "TEST ?")
    }

    @Test("(f) Several custom-titles: the last one wins")
    func lastCustomTitleWins() throws {
        let url = TranscriptFixtures.write(
            TranscriptFixtures.customTitleLine("first rename") + "\n"
                + TranscriptFixtures.customTitleLine("second rename") + "\n"
                + TranscriptFixtures.customTitleLine("final rename"))
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptReader.title(ofTranscriptAt: url) == "final rename")
    }

    @Test("(e) A transcript with neither title yields nil (caller falls back to the folder)")
    func noTitleYieldsNil() throws {
        let url = TranscriptFixtures.write(TranscriptFixtures.sessionTail)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptReader.title(ofTranscriptAt: url) == nil)
    }

    @Test("A missing or corrupted transcript yields no title without crashing")
    func corruptedTranscriptYieldsNilTitle() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript-fixture-\(UUID().uuidString)-missing.jsonl")
        #expect(TranscriptReader.title(ofTranscriptAt: missing) == nil)

        let url = TranscriptFixtures.write("""
            this is not json at all
            {"type":"custom-title","customTitle": broken
            \u{0}\u{1}binary garbage\u{FFFD}
            """)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(TranscriptReader.title(ofTranscriptAt: url) == nil)
    }

    @Test("A /rename far from the end is still found with the default cap (regression: a small cap missed it) #32")
    func renameFoundFarFromEnd() throws {
        // The custom-title can sit well before EOF when a long turn (and frozen
        // ai-title re-emissions) followed it. The default cap (4 MB) must reach
        // it — and the rename must still win over the more recent ai-titles.
        let fillerLine = TranscriptFixtures.aiTitleLine("Frozen auto title")
        let fillerCount = (300 * 1024) / (fillerLine.count + 1) + 1
        let filler = Array(repeating: fillerLine, count: fillerCount).joined(separator: "\n")
        let contents = TranscriptFixtures.customTitleLine("Renamed then a long turn") + "\n" + filler
        let url = TranscriptFixtures.write(contents)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(TranscriptReader.title(ofTranscriptAt: url) == "Renamed then a long turn")
    }
}
