import Combine
import Foundation
import IslandStore

/// The Relais (issue #157, ADR-0014): follows the store and the Quotas and
/// pushes the Instantané to the Totem — `POST http://<address>/snapshot`,
/// `X-Island-Token` header.
///
/// Never blocking: the POST runs off the main thread, the store never waits
/// on it, and at most one request is in flight while only the most recent
/// Instantané waits behind it.
@MainActor
public final class TotemRelay {
    private let sessions: AnyPublisher<[Session], Never>
    private let quotas: AnyPublisher<Quotas?, Never>
    private let transport: RelayTransport
    private let heartbeatInterval: Duration
    private let throttle: DispatchQueue.SchedulerTimeType.Stride
    private let now: () -> Date

    private var cancellable: AnyCancellable?
    private var enabled = false
    private var target: RelayTarget?
    /// The latest Instantané of the chain (nil until its first emission).
    private var current: TotemSnapshot?
    /// What was last handed to the transport (in flight or done).
    private var lastSent: TotemSnapshot?
    /// When the last request was handed to the transport.
    private var lastSentAt: Date?
    private var heartbeat: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    /// The most recent Instantané waiting behind the in-flight request.
    private var pending: Outgoing?
    /// Outcome of the last request, to keep steady heartbeats out of the trace.
    private var lastOutcome: String?
    /// Set by ``shutdown(timeout:)``: the Relais never sends again.
    private var isShutDown = false

    private struct Outgoing {
        let snapshot: TotemSnapshot
        let target: RelayTarget
    }

    public convenience init(
        store: SessionStore,
        quotaStore: QuotaStore,
        transport: RelayTransport = .live,
        heartbeatInterval: Duration = .seconds(10),
        throttle: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(200),
        now: @escaping () -> Date = Date.init
    ) {
        self.init(
            sessions: store.$sessions.eraseToAnyPublisher(),
            quotas: quotaStore.$quotas.eraseToAnyPublisher(),
            transport: transport,
            heartbeatInterval: heartbeatInterval,
            throttle: throttle,
            now: now
        )
    }

    init(
        sessions: AnyPublisher<[Session], Never>,
        quotas: AnyPublisher<Quotas?, Never>,
        transport: RelayTransport,
        heartbeatInterval: Duration,
        throttle: DispatchQueue.SchedulerTimeType.Stride,
        now: @escaping () -> Date
    ) {
        self.sessions = sessions
        self.quotas = quotas
        self.transport = transport
        self.heartbeatInterval = heartbeatInterval
        self.throttle = throttle
        self.now = now
    }

    /// Starts following the store and the Quotas. `@Published` emits at
    /// `willSet`: only the chain's values are used, never a re-read of
    /// `store.sessions` / `quotaStore.quotas` (they still hold the old value).
    public func start() {
        cancellable = sessions.combineLatest(quotas)
            .map { TotemSnapshot.make(sessions: $0, quotas: $1) }
            .removeDuplicates()
            .throttle(for: throttle, scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] snapshot in
                MainActor.assumeIsolated { self?.snapshotDidChange(snapshot) }
            }
    }

    /// On: pushes the current Instantané at once, then follows changes and
    /// beats. Off: stops the heartbeat and sends one last empty Instantané,
    /// best-effort, so the Totem never keeps a stale Halo — then nothing.
    public func setEnabled(_ enabled: Bool) {
        guard !isShutDown, enabled != self.enabled else { return }
        self.enabled = enabled
        forgetLastSent()
        if enabled {
            startHeartbeat()
            pushCurrentIfChanged()
        } else {
            stopHeartbeat()
            if let target {
                // Behind an in-flight request it replaces any pending
                // Instantané: the empty one is the last word.
                submit(Outgoing(snapshot: .empty, target: target))
            } else {
                pending = nil
            }
        }
    }

    /// A new address or token: the new Totem has seen nothing yet, so the
    /// current Instantané goes out at once even if unchanged. Nil (settings
    /// incomplete) sends nothing until a target is set again.
    public func setTarget(_ target: RelayTarget?) {
        guard !isShutDown, target != self.target else { return }
        self.target = target
        forgetLastSent()
        pushCurrentIfChanged()
    }

    /// Whether ``shutdown(timeout:)`` has anything to do: the Relais is on, or
    /// its last empty Instantané (from turning off) is still on its way. The
    /// app only defers termination when it does.
    public var needsShutdown: Bool {
        !isShutDown && (enabled || inFlight != nil || pending != nil)
    }

    /// Clean app termination (PRD US10): stops following the store and the
    /// heartbeat, cancels the in-flight request and sends the empty
    /// Instantané, giving up after `timeout` so quitting is never held
    /// hostage by an unreachable Totem. A Relais that is off only lets its
    /// last empty Instantané (from turning off) finish, within the same bound.
    /// Afterwards nothing is ever sent again.
    public func shutdown(timeout: Duration = .seconds(1)) async {
        guard !isShutDown else { return }
        isShutDown = true
        cancellable = nil
        stopHeartbeat()
        // Off, the only possible pending Instantané is the empty one.
        let last = enabled ? target.map { Outgoing(snapshot: .empty, target: $0) } : pending
        enabled = false
        pending = nil
        let running = inFlight

        if let last {
            running?.cancel()
            let transport = transport
            let state = last.snapshot.state.rawValue
            let body: Data
            do {
                body = try last.snapshot.encode(sentAt: now())
            } catch {
                Self.log("totem relay shutdown: empty Instantané not encodable: \(error)")
                return
            }
            await Self.bounded(by: timeout) {
                do {
                    let status = try await transport.post(body, last.target)
                    Self.log("totem relay shutdown push state=\(state) → HTTP \(status)")
                } catch {
                    Self.log("totem relay shutdown push state=\(state) failed: \(Self.trace(of: error))")
                }
            }
        } else if let running {
            await Self.bounded(by: timeout) {
                await withTaskCancellationHandler {
                    await running.value
                } onCancel: {
                    running.cancel()
                }
            }
        }
    }

    /// Runs `work` for at most `timeout`, then cancels it (the transport
    /// honors cancellation, so the wait really ends at the bound).
    private nonisolated static func bounded(
        by timeout: Duration,
        _ work: @escaping @Sendable () async -> Void
    ) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await work() }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    /// Pure push decision: a changed Instantané goes out at once; an
    /// unchanged one only when the heartbeat interval has elapsed since the
    /// last request (the heartbeat bounds how stale a Halo can get).
    nonisolated static func shouldPush(
        current: TotemSnapshot,
        lastSent: TotemSnapshot?,
        lastSentAt: Date?,
        now: Date,
        heartbeatInterval: TimeInterval
    ) -> Bool {
        guard current == lastSent, let lastSentAt else { return true }
        let elapsed = now.timeIntervalSince(lastSentAt)
        // A wall clock set back must not postpone the heartbeat by the jump.
        return elapsed < 0 || elapsed >= heartbeatInterval
    }

    /// One heartbeat: re-pushes the unchanged Instantané once the interval
    /// has elapsed since the last request. Internal so tests drive it with a
    /// fake clock, bypassing the sleeping loop.
    func heartbeatTick() {
        guard enabled, let target, let current,
            Self.shouldPush(
                current: current, lastSent: lastSent, lastSentAt: lastSentAt,
                now: now(), heartbeatInterval: heartbeatSeconds)
        else { return }
        submit(Outgoing(snapshot: current, target: target))
    }

    private var heartbeatSeconds: TimeInterval {
        let (seconds, attoseconds) = heartbeatInterval.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) * 1e-18
    }

    /// Sleeps until the heartbeat is due — measured from the last request,
    /// so a push on change postpones it and the gap never exceeds the interval.
    private func startHeartbeat() {
        heartbeat?.cancel()
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                guard let delay = self?.nextHeartbeatDelay() else { return }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.heartbeatTick()
            }
        }
    }

    private func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    private func nextHeartbeatDelay() -> Duration {
        guard let lastSentAt else { return heartbeatInterval }
        let remaining = heartbeatSeconds - now().timeIntervalSince(lastSentAt)
        // Never longer than one interval, even if the wall clock went back.
        return remaining > 0 && remaining <= heartbeatSeconds ? .seconds(remaining) : heartbeatInterval
    }

    /// The next Instantané is treated as a change and goes out at once.
    private func forgetLastSent() {
        lastSent = nil
        lastSentAt = nil
    }

    private func snapshotDidChange(_ snapshot: TotemSnapshot) {
        current = snapshot
        pushCurrentIfChanged()
    }

    private func pushCurrentIfChanged() {
        guard enabled, let target, let current else { return }
        if inFlight != nil {
            // The in-flight request carries `lastSent`: only a different
            // Instantané needs to wait behind it (the most recent wins).
            pending = current == lastSent ? nil : Outgoing(snapshot: current, target: target)
        } else if current != lastSent {
            send(Outgoing(snapshot: current, target: target))
        }
    }

    private func submit(_ outgoing: Outgoing) {
        if inFlight != nil {
            pending = outgoing
        } else {
            send(outgoing)
        }
    }

    private func send(_ outgoing: Outgoing) {
        let isRepeat = outgoing.snapshot == lastSent
        lastSent = outgoing.snapshot
        lastSentAt = now()
        let transport = transport
        let sentAt = now()
        inFlight = Task { [weak self] in
            let outcome: String
            do {
                let body = try outgoing.snapshot.encode(sentAt: sentAt)
                outcome = "HTTP \(try await transport.post(body, outgoing.target))"
            } catch {
                outcome = "failed: \(Self.trace(of: error))"
            }
            self?.requestDidFinish(outgoing, isRepeat: isRepeat, outcome: outcome)
        }
    }

    /// Traces every push of a new Instantané, but a heartbeat repeat only
    /// when its outcome differs from the previous one (failure, recovery):
    /// a steady Totem — or a steadily unreachable one — is one line, not one
    /// every ~10 s.
    private func requestDidFinish(_ outgoing: Outgoing, isRepeat: Bool, outcome: String) {
        if !isRepeat || outcome != lastOutcome {
            let snapshot = outgoing.snapshot
            let counts = snapshot.counts
            Self.log("totem relay push state=\(snapshot.state.rawValue)"
                + " counts=waiting:\(counts.waiting),done:\(counts.done),working:\(counts.working),idle:\(counts.idle)"
                + (snapshot.shutdown ? " shutdown" : "")
                + (isRepeat ? " (heartbeat)" : "")
                + " → \(outcome)")
        }
        lastOutcome = outcome
        inFlight = nil
        if let next = pending {
            pending = nil
            send(next)
        }
    }

    /// One line, complete: every error in the underlying chain with its
    /// domain, code and description, plus the network path when URLSession
    /// reports one — `unsatisfied (Local network prohibited)` is how a denied
    /// Local Network permission shows, unlike a refused or timed-out Totem.
    nonisolated static func trace(of error: Error) -> String {
        var parts: [String] = []
        var next: NSError? = error as NSError
        while let current = next {
            var part = "\(current.domain) \(current.code)"
            if let description = current.userInfo[NSLocalizedDescriptionKey] as? String {
                part += " \"\(description)\""
            }
            if let path = current.userInfo["_NSURLErrorNWPathKey"] {
                part += " path=\(path)"
            }
            parts.append(part)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " ← ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private nonisolated static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        print("island: [\(timestamp)] \(message)")
    }
}
