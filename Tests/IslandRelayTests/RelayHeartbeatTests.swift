import Combine
import Foundation
import Testing
@testable import IslandRelay
import IslandStore

/// The heartbeat clock (issue #157): the pure push decision, and the tick
/// driven with a fake clock instead of waiting ~10 s.
@MainActor
struct RelayHeartbeatTests {
    nonisolated static let idle = TotemSnapshot.make(sessions: [], quotas: nil)
    nonisolated static let waiting = TotemSnapshot(
        state: .waiting, counts: .init(waiting: 1, done: 0, working: 0, idle: 0),
        quotas: nil, shutdown: false)
    nonisolated static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    @Test(
        "Push decision: a change goes out at once, an unchanged Instantané only once the heartbeat is due",
        arguments: [
            // (current, lastSent, seconds since last request or nil, expected)
            (idle, nil as TotemSnapshot?, nil as TimeInterval?, true),
            (waiting, idle, 0.1, true),
            (idle, idle, 9.9, false),
            (idle, idle, 10, true),
            (idle, idle, 25, true),
            // The wall clock went back (manual change, NTP): never wait it out.
            (idle, idle, -3600, true),
        ]
    )
    func pushDecision(
        current: TotemSnapshot, lastSent: TotemSnapshot?, elapsed: TimeInterval?, expected: Bool
    ) {
        #expect(TotemRelay.shouldPush(
            current: current,
            lastSent: lastSent,
            lastSentAt: elapsed.map { Self.t0.addingTimeInterval(-$0) },
            now: Self.t0,
            heartbeatInterval: 10
        ) == expected)
    }

    @Test("A heartbeat tick re-pushes only once the interval has elapsed since the last request")
    func tickHonorsInterval() async throws {
        var clock = Self.t0
        let recorder = PostRecorder()
        let sessions = CurrentValueSubject<[Session], Never>([])
        let relay = TotemRelay(
            sessions: sessions.eraseToAnyPublisher(),
            quotas: Just(nil).eraseToAnyPublisher(),
            transport: recorder.transport,
            heartbeatInterval: .seconds(10),
            throttle: .milliseconds(1),
            now: { clock }
        )
        relay.setTarget(RelayTarget(endpoint: URL(string: "http://127.0.0.1:9/snapshot")!, token: "t"))
        relay.setEnabled(true)
        relay.start()
        try await recorder.waitForCount(1)

        clock = Self.t0.addingTimeInterval(9)
        relay.heartbeatTick()
        try await Task.sleep(for: .milliseconds(50))
        #expect(recorder.count == 1)

        clock = Self.t0.addingTimeInterval(10)
        relay.heartbeatTick()
        try await recorder.waitForCount(2)
    }
}

/// Records every POST body instead of hitting the network.
final class PostRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [Data] = []

    var count: Int { lock.withLock { bodies.count } }

    var transport: RelayTransport {
        RelayTransport { [self] body, _ in
            lock.withLock { bodies.append(body) }
            return 200
        }
    }

    func waitForCount(_ expected: Int, timeout: TimeInterval = 2) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while count < expected {
            guard Date() < deadline else { throw FakeTotemError.timedOut(received: count) }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
