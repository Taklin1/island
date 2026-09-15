import Foundation
import Testing

import IslandStore

/// The Totem Instantané (issue #156, ADR-0013/0015): pure aggregate of the
/// Sessions and Quotas, and its JSON contract pinned by the shared fixtures in
/// `firmware/contract/`.
struct TotemSnapshotTests {
    private static func session(
        _ id: String, _ state: SessionState, ack needsAcknowledgement: Bool = false
    ) -> Session {
        Session(id: id, state: state, agent: "claude-code", needsAcknowledgement: needsAcknowledgement)
    }

    struct Case: CustomTestStringConvertible, Sendable {
        let label: String
        let sessions: [Session]
        let state: TotemSnapshot.State
        let counts: TotemSnapshot.Counts
        var testDescription: String { label }
    }

    static let cases: [Case] = [
        Case(label: "zero Session is idle with zero counts", sessions: [],
             state: .idle, counts: .init(waiting: 0, done: 0, working: 0, idle: 0)),
        Case(label: "unacknowledged waiting wins", sessions: [
            session("a", .waiting, ack: true),
            session("b", .ended, ack: true),
            session("c", .running),
            session("d", .idle),
        ], state: .waiting, counts: .init(waiting: 1, done: 1, working: 1, idle: 1)),
        Case(label: "unacknowledged ended is done", sessions: [
            session("a", .ended, ack: true),
            session("b", .running),
            session("c", .running),
        ], state: .done, counts: .init(waiting: 0, done: 1, working: 2, idle: 0)),
        Case(label: "running is working", sessions: [
            session("a", .running),
            session("b", .idle),
        ], state: .working, counts: .init(waiting: 0, done: 0, working: 1, idle: 1)),
        Case(label: "acknowledged waiting no longer weighs on state but still counts as waiting", sessions: [
            session("a", .waiting),
            session("b", .idle),
        ], state: .idle, counts: .init(waiting: 1, done: 0, working: 0, idle: 1)),
        Case(label: "acknowledged waiting yields to a pending done", sessions: [
            session("a", .waiting),
            session("b", .ended, ack: true),
        ], state: .done, counts: .init(waiting: 1, done: 1, working: 0, idle: 0)),
        Case(label: "everything acknowledged is idle, counts stay raw", sessions: [
            session("a", .waiting),
            session("b", .ended),
            session("c", .waiting),
        ], state: .idle, counts: .init(waiting: 2, done: 1, working: 0, idle: 0)),
    ]

    @Test("State follows the Priorité d'état over unacknowledged Sessions; counts are raw states", arguments: cases)
    func stateAndCounts(_ testCase: Case) {
        let snapshot = TotemSnapshot.make(sessions: testCase.sessions, quotas: nil)

        #expect(snapshot.state == testCase.state)
        #expect(snapshot.counts == testCase.counts)
        #expect(snapshot.shutdown == false)
    }

    // MARK: - Contract (golden, byte for byte)

    /// Repo root, reached from this file's compile-time path: SwiftPM refuses
    /// resources outside the target folder, and the fixtures belong to
    /// `firmware/contract/` (ADR-0015), shared with the firmware tests.
    private static func contractFixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // IslandStoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
        return try Data(contentsOf: root.appendingPathComponent("firmware/contract/\(name)"))
    }

    /// Fractional on purpose: `sentAt` is whole Unix epoch seconds, floored.
    private static let sentAt = Date(timeIntervalSince1970: 1_738_420_000.6)

    @Test("The nominal Instantané encodes to firmware/contract/snapshot-nominal.json byte for byte")
    func nominalGolden() throws {
        let sessions = [
            // Acknowledged waiting: counted as waiting, no longer weighs on state.
            Self.session("s-waiting", .waiting),
            Self.session("s-done", .ended, ack: true),
            Self.session("s-work-1", .running),
            Self.session("s-work-2", .running),
            Self.session("s-idle", .idle),
        ]
        let quotas = Quotas(
            fiveHour: RateLimitWindow(usedPercentage: 23.5, resetsAt: Date(timeIntervalSince1970: 1_738_425_600)),
            // No reset known: the key is omitted, never null.
            sevenDay: RateLimitWindow(usedPercentage: 41.2)
        )

        let encoded = try TotemSnapshot.make(sessions: sessions, quotas: quotas).encode(sentAt: Self.sentAt)

        #expect(encoded == (try Self.contractFixture("snapshot-nominal.json")),
                "\(String(decoding: encoded, as: UTF8.self))")
    }

    @Test("The empty Instantané encodes to firmware/contract/snapshot-empty.json byte for byte")
    func emptyGolden() throws {
        let empty = TotemSnapshot.empty
        #expect(empty.state == .idle)
        #expect(empty.counts == .init(waiting: 0, done: 0, working: 0, idle: 0))
        #expect(empty.quotas == nil)
        #expect(empty.shutdown)

        let encoded = try empty.encode(sentAt: Self.sentAt)

        #expect(encoded == (try Self.contractFixture("snapshot-empty.json")),
                "\(String(decoding: encoded, as: UTF8.self))")
    }

    @Test("Absent Quotas omit the quotas key; equality ignores the emission time")
    func absentQuotasAreOmitted() throws {
        let snapshot = TotemSnapshot.make(sessions: [], quotas: nil)
        let json = String(decoding: try snapshot.encode(sentAt: Self.sentAt), as: UTF8.self)

        #expect(json == #"{"counts":{"done":0,"idle":0,"waiting":0,"working":0},"sentAt":1738420000,"shutdown":false,"state":"idle","v":1}"#)
        #expect(snapshot == TotemSnapshot.make(sessions: [], quotas: nil))
        // Both windows absent is the same as no Quotas at all.
        #expect(TotemSnapshot.make(sessions: [], quotas: Quotas()) == snapshot)
    }

    // MARK: - Nothing of a Session leaves the Mac (ADR-0013)

    @Test("No Session text, identifier or context key ever reaches the JSON; no context nor halo field")
    @MainActor
    func noSessionTextLeaks() throws {
        func sentinel(_ field: String) -> String { "SENTINEL-\(field)" }
        let question = PendingQuestion(prompt: sentinel("pendingQuestion.prompt"), options: [
            .init(label: sentinel("options.label"), description: sentinel("options.description")),
        ])
        let stash = Session.QuestionStash(
            tool: sentinel("questionStash.tool"),
            question: PendingQuestion(prompt: sentinel("questionStash.prompt"), options: [
                .init(label: sentinel("questionStash.label"), description: sentinel("questionStash.description")),
            ])
        )
        let sessions = SessionState.allStatesForTest.map { state in
            Session(
                id: sentinel("id-\(state)"),
                state: state,
                cwd: sentinel("cwd"),
                title: sentinel("title"),
                agent: sentinel("agent"),
                terminal: sentinel("terminal"),
                lastPrompt: sentinel("lastPrompt"),
                currentTool: sentinel("currentTool"),
                lastSummary: TurnSummary(
                    text: sentinel("lastSummary.text"),
                    filesModified: [sentinel("filesModified")]
                ),
                needsAcknowledgement: true,
                pendingQuestion: question,
                waitingMessage: sentinel("waitingMessage"),
                questionStash: stash
            )
        }
        // Quotas and per-Session context come from the same statusline store.
        let quotaStore = QuotaStore()
        let statusline = """
        {
          "session_id": "\(sentinel("contextBySession-key"))",
          "context_window": { "used_percentage": 87.3 },
          "rate_limits": {
            "five_hour": { "used_percentage": 12.0, "resets_at": 1738425600 },
            "seven_day": { "used_percentage": 64.9 }
          }
        }
        """
        quotaStore.apply(try #require(QuotaUpdate(statuslineJSON: Data(statusline.utf8))))
        #expect(quotaStore.contextBySession.keys.contains(sentinel("contextBySession-key")))

        let data = try TotemSnapshot.make(sessions: sessions, quotas: quotaStore.quotas)
            .encode(sentAt: Self.sentAt)
        let json = String(decoding: data, as: UTF8.self)

        #expect(!json.contains("SENTINEL"), "\(json)")

        // Structure is closed: no context percentage, no halo, anywhere.
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["v", "state", "counts", "quotas", "sentAt", "shutdown"])
        let counts = try #require(object["counts"] as? [String: Any])
        #expect(Set(counts.keys) == ["waiting", "done", "working", "idle"])
        let windows = try #require(object["quotas"] as? [String: Any])
        #expect(Set(windows.keys) == ["fiveHour", "sevenDay"])
        for case let window as [String: Any] in windows.values {
            #expect(Set(window.keys).isSubset(of: ["usedPercentage", "resetsAt"]))
        }
        #expect(!json.contains("context"))
        #expect(!json.contains("halo"))
    }

    @Test("An unrepresentable reset time is omitted rather than trapping")
    func absurdResetIsOmitted() throws {
        let quotas = Quotas(fiveHour: RateLimitWindow(usedPercentage: 10, resetsAt: Date(timeIntervalSince1970: 1e300)))

        let snapshot = TotemSnapshot.make(sessions: [], quotas: quotas)

        #expect(snapshot.quotas?.fiveHour == TotemSnapshot.Window(usedPercentage: 10, resetsAt: nil))
    }
}

private extension SessionState {
    static let allStatesForTest: [SessionState] = [.idle, .running, .ended, .waiting]
}
