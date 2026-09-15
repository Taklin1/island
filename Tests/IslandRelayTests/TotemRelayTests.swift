import Foundation
import Testing
import IslandRelay
import IslandStore

/// The Relais end to end (issue #157, ADR-0014): real `SessionStore` and
/// `QuotaStore`, the live URLSession transport, a fake Totem on 127.0.0.1.
/// Assertions are on what the Totem receives — never the relay internals.
@MainActor
@Suite(.serialized)
struct TotemRelayTests {
    @Test("An enabled Relais pushes the Instantané to POST /snapshot with the X-Island-Token header")
    func pushesSnapshotWithToken() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem)
        harness.relay.setEnabled(true)

        try await totem.waitForRequests(count: 1)
        harness.store.apply(Self.event("s1", .sessionStarted))
        let requests = try await totem.waitForRequests(count: 2)

        #expect(requests.allSatisfy { $0.method == "POST" && $0.path == "/snapshot" })
        #expect(requests.allSatisfy { $0.headers["x-island-token"] == RelayHarness.token })
        #expect(requests.allSatisfy { $0.headers["content-type"] == "application/json" })
        // The ESP32 closes after each answer: never rely on keep-alive.
        #expect(requests.allSatisfy { $0.headers["connection"]?.lowercased() == "close" })
        let last = totem.snapshots[1]
        #expect(last["state"] as? String == "idle")
        #expect((last["counts"] as? [String: Int])?["idle"] == 1)
        #expect(last["shutdown"] as? Bool == false)
    }

    @Test("One push per Instantané change, none when only Session text or identical Quotas are republished")
    func pushesOnlyOnChange() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem)
        harness.store.apply(Self.event("s1", .sessionStarted))
        harness.relay.setEnabled(true)
        try await totem.waitForRequests(count: 1)

        // Same states, same percentages: the Instantané is unchanged.
        harness.store.setTitle("Renamed", forSessionID: "s1")
        harness.quotaStore.apply(try Self.statusline(fiveHour: 42))
        try await totem.waitForRequests(count: 2)
        harness.quotaStore.apply(try Self.statusline(fiveHour: 42))
        harness.quotaStore.apply(try Self.statusline(fiveHour: 42.2)) // rounds to 42 too
        harness.store.setTitle("Renamed again", forSessionID: "s1")
        try await Task.sleep(for: .milliseconds(300))
        #expect(totem.requests.count == 2)

        harness.store.apply(Self.event("s1", .promptSubmitted(prompt: "Go")))
        try await totem.waitForRequests(count: 3)
        try await Task.sleep(for: .milliseconds(300))
        #expect(totem.requests.count == 3)
        #expect(totem.snapshots[1]["quotas"] as? [String: [String: Int]] == ["fiveHour": ["usedPercentage": 42]])
        #expect(totem.snapshots[2]["state"] as? String == "working")
    }

    @Test("Without any change the unchanged Instantané is re-pushed on every heartbeat")
    func heartbeatRepushesUnchangedSnapshot() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem, heartbeatInterval: .milliseconds(100))
        harness.store.apply(Self.event("s1", .sessionStarted))
        harness.relay.setEnabled(true)

        try await totem.waitForRequests(count: 4, timeout: 2)
        let bodies = totem.snapshots.map { $0.filter { $0.key != "sentAt" } as NSDictionary }
        #expect(Set(bodies).count == 1)
    }

    @Test("A Relais never enabled sends nothing — no push, no heartbeat")
    func offByDefaultSendsNothing() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem, heartbeatInterval: .milliseconds(50))
        harness.store.apply(Self.event("s1", .sessionStarted))
        harness.store.apply(Self.event("s1", .waitingForUser(message: nil)))

        try await Task.sleep(for: .milliseconds(300))
        #expect(totem.requests.isEmpty)
    }

    @Test("Turning the Relais off sends one empty Instantané, then no POST and no heartbeat ever")
    func turningOffSendsEmptyThenNothing() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem, heartbeatInterval: .milliseconds(100))
        harness.store.apply(Self.event("s1", .waitingForUser(message: nil)))
        harness.relay.setEnabled(true)
        try await totem.waitForRequests(count: 1)

        harness.relay.setEnabled(false)
        #expect(harness.relay.needsShutdown) // the empty Instantané is on its way
        try await totem.waitForRequests(count: 2)
        harness.store.apply(Self.event("s1", .promptSubmitted(prompt: "Go")))
        try await Task.sleep(for: .milliseconds(400))

        #expect(totem.requests.count == 2)
        #expect(totem.snapshots[0]["state"] as? String == "waiting")
        #expect(totem.snapshots[1]["shutdown"] as? Bool == true)
        #expect(totem.snapshots[1]["state"] as? String == "idle")
    }

    @Test("Turning the Relais back on pushes the current Instantané at once")
    func turningBackOnPushesImmediately() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem)
        harness.store.apply(Self.event("s1", .waitingForUser(message: nil)))
        harness.relay.setEnabled(true)
        try await totem.waitForRequests(count: 1)
        harness.relay.setEnabled(false)
        try await totem.waitForRequests(count: 2)

        harness.relay.setEnabled(true)
        try await totem.waitForRequests(count: 3)
        #expect(totem.snapshots[2]["state"] as? String == "waiting")
        #expect(totem.snapshots[2]["shutdown"] as? Bool == false)
    }

    @Test("Changing the address or the token pushes the unchanged Instantané at once to the new target")
    func changingTargetPushesImmediately() async throws {
        let first = try await FakeTotemServer()
        let second = try await FakeTotemServer()
        let harness = RelayHarness(totem: first)
        harness.relay.setEnabled(true)
        try await first.waitForRequests(count: 1)

        harness.relay.setTarget(RelayTarget(endpoint: second.endpoint, token: RelayHarness.token))
        try await second.waitForRequests(count: 1)

        harness.relay.setTarget(RelayTarget(endpoint: second.endpoint, token: "rotated"))
        let requests = try await second.waitForRequests(count: 2)
        #expect(requests[1].headers["x-island-token"] == "rotated")

        // Re-applying the very same target is not a change.
        harness.relay.setTarget(RelayTarget(endpoint: second.endpoint, token: "rotated"))
        try await Task.sleep(for: .milliseconds(200))
        #expect(second.requests.count == 2)
        #expect(first.requests.count == 1)
    }

    @Test("Shutdown sends the empty Instantané before returning, then nothing ever again")
    func shutdownSendsEmptyThenNothing() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem, heartbeatInterval: .milliseconds(100))
        harness.store.apply(Self.event("s1", .waitingForUser(message: nil)))
        harness.relay.setEnabled(true)
        try await totem.waitForRequests(count: 1)
        #expect(harness.relay.needsShutdown)

        await harness.relay.shutdown()
        #expect(!harness.relay.needsShutdown)
        #expect(totem.requests.count == 2)
        #expect(totem.snapshots.last?["shutdown"] as? Bool == true)

        harness.store.apply(Self.event("s1", .promptSubmitted(prompt: "Go")))
        harness.relay.setEnabled(false)
        harness.relay.setEnabled(true)
        try await Task.sleep(for: .milliseconds(400))
        #expect(totem.requests.count == 2)
    }

    @Test("Shutdown of a Relais that is off returns at once without any POST")
    func shutdownWhileOffSendsNothing() async throws {
        let totem = try await FakeTotemServer()
        let harness = RelayHarness(totem: totem)
        #expect(!harness.relay.needsShutdown)
        let started = ContinuousClock.now

        await harness.relay.shutdown()

        #expect(ContinuousClock.now - started < .milliseconds(100))
        try await Task.sleep(for: .milliseconds(100))
        #expect(totem.requests.isEmpty)
    }

    @Test("Shutdown against a mute Totem gives up within its bound")
    func shutdownIsBounded() async throws {
        let totem = try await FakeTotemServer(behavior: .mute)
        let harness = RelayHarness(totem: totem, requestTimeout: 10)
        harness.relay.setEnabled(true)
        try await totem.waitForRequests(count: 1)
        let started = ContinuousClock.now

        await harness.relay.shutdown(timeout: .milliseconds(300))

        #expect(ContinuousClock.now - started < .seconds(1))
    }

    @Test("A mute Totem never blocks the Événements: one request in flight, the most recent Instantané waits behind it")
    func muteTotemNeverBlocks() async throws {
        let totem = try await FakeTotemServer(behavior: .mute)
        let harness = RelayHarness(totem: totem, requestTimeout: 2)
        harness.relay.setEnabled(true)
        try await totem.waitForRequests(count: 1)

        // A burst of Événements while the first request hangs.
        let started = ContinuousClock.now
        for index in 0 ..< 20 {
            harness.store.apply(Self.event("s\(index)", .sessionStarted))
            try await Task.sleep(for: .milliseconds(5))
        }
        harness.store.apply(Self.event("s0", .waitingForUser(message: nil)))
        #expect(harness.store.sessions.count == 20)
        #expect(harness.store.sessions.first { $0.id == "s0" }?.state == .waiting)
        try await Self.expectMainActorResponsive()
        // Well under the 2 s request timeout: nothing waited on the Totem.
        #expect(ContinuousClock.now - started < .seconds(1))
        #expect(totem.requests.count == 1)

        // Once the hung request times out, only the latest Instantané follows.
        try await totem.waitForRequests(count: 2, timeout: 5)
        try await Task.sleep(for: .milliseconds(100))
        #expect(totem.requests.count == 2)
        #expect(totem.snapshots[1]["state"] as? String == "waiting")
        #expect((totem.snapshots[1]["counts"] as? [String: Int])?["idle"] == 19)
    }

    @Test("A Totem that is absent (closed port) never blocks the Événements")
    func absentTotemNeverBlocks() async throws {
        let port = try await FakeTotemServer.closedPort()
        let harness = RelayHarness(
            totem: nil,
            endpoint: URL(string: "http://127.0.0.1:\(port)/snapshot")!,
            heartbeatInterval: .milliseconds(150)
        )
        harness.relay.setEnabled(true)

        for index in 0 ..< 20 {
            harness.store.apply(Self.event("s\(index)", .sessionStarted))
            try await Task.sleep(for: .milliseconds(10))
            try await Self.expectMainActorResponsive()
        }
        #expect(harness.store.sessions.count == 20)
        try await Task.sleep(for: .milliseconds(400))
        #expect(harness.store.sessions.count == 20)
    }

    /// The main actor still runs a freshly scheduled job promptly.
    static func expectMainActorResponsive() async throws {
        let scheduled = ContinuousClock.now
        let ran = await Task { @MainActor in ContinuousClock.now }.value
        #expect(ran - scheduled < .milliseconds(250))
    }

    static func statusline(fiveHour: Double) throws -> QuotaUpdate {
        let json = #"{"session_id":"s1","rate_limits":{"five_hour":{"used_percentage":\#(fiveHour)}}}"#
        return try #require(QuotaUpdate(statuslineJSON: Data(json.utf8)))
    }

    static func event(_ id: String, _ kind: AgentEventKind) -> AgentEvent {
        AgentEvent(sessionID: id, kind: kind, agent: "claude-code")
    }
}

/// Real stores + a relay wired to the fake Totem with test-sized timings.
@MainActor
final class RelayHarness {
    static let token = "totem-test-token"

    let store = SessionStore(sweepInterval: nil)
    let quotaStore = QuotaStore()
    let relay: TotemRelay

    init(
        totem: FakeTotemServer?,
        endpoint: URL? = nil,
        heartbeatInterval: Duration = .seconds(60),
        requestTimeout: TimeInterval = 0.5
    ) {
        relay = TotemRelay(
            store: store,
            quotaStore: quotaStore,
            transport: .live(requestTimeout: requestTimeout, resourceTimeout: requestTimeout + 0.5),
            heartbeatInterval: heartbeatInterval,
            throttle: .milliseconds(20)
        )
        if let url = endpoint ?? totem?.endpoint {
            relay.setTarget(RelayTarget(endpoint: url, token: Self.token))
        }
        relay.start()
    }
}
